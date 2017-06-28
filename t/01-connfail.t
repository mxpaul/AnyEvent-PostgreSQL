#!/usr/bin/env perl
use FindBin qw($Bin);
use lib "$Bin/../lib";
use Test::More;

use AnyEvent;
sub AE::cvt(;$) { my $delay = (shift) // 1;
	my ($cv, $t);
	AE::now_update;
	$t = AE::timer $delay, 0, sub {undef $t; $cv->croak("cvt: timeout after $delay seconds")};
	$cv = AE::cv sub {undef $t};
	return $cv;
}

use Test::PostgreSQL;
use Carp;
use URI;
use Data::Dumper;
#use Devel::Leak;

use AnyEvent::PostgreSQL;

sub uri_to_conninfo {
	my $uri = shift or croak 'Need uri';
	my $u = URI->new($uri);
	$u->scheme('http');
	my ($login, $password) = split(':', $u->userinfo);
	(my $dbname = $u->path) =~ s{/}{}g;
	{
		server        => $u->host_port(),
		dbname        => $dbname,
		login         => $login,
		password      => $password//'',
	}
}

#my $handle;
#my $count = Devel::Leak::NoteSV($handle);
#diag "Count at start: $count";
#$count = Devel::Leak::CheckSV($handle);
#diag "Count after code: $count";
#use Devel::FindRef;
{
	my $addr = '127.0.0.1:28761';
	my $pool;
	$pool = AnyEvent::PostgreSQL->new(
		name            => 'wrongport',
		server          => $addr,
		dbname          => 'testdb',
		login           => 'PG_USER',
		password        => 'PG_PASS',
		connect_timeout => 0.0001,
		on_connfail     => (my $connfail = AE::cvt),
	);
	is($pool->server, $addr, 'new() arg server is stored in object');
	is($pool->dbname, 'testdb', 'new() arg dbname is stored in object');
	is($pool->login, 'PG_USER', 'new() arg login is stored in object');
	is($pool->password, 'PG_PASS', 'new() arg password is stored in object');
	$pool->connect;

	my ($self, $event) = eval {$connfail->recv;}; fail $@ if $@;
	is($self, $pool, 'pool object passed as first argument to connfail_callback');
	is(ref $event, 'HASH', 'connfail returns event description as HASH');
	like($event->{reason}, qr/connection.+(fail|refuse).*127.0.0.1.*28761/i,
		'reason has descrpitive message after connection has failed with host and port identified');
	$pool->disconnect;
	## ##warn "!!!!!!!!!!!!!!!" .Devel::FindRef::track \$pool;
	## ##@references = Devel::FindRef::find \$pool;
	## ##for my $item (@references) {
	## ##	my $ref = Devel::FindRef::ptr2ref($item->[1]);
	## ##	warn $ref;
	## ##}
	#undef $pool;
}

my $pgserv = Test::PostgreSQL->new();
fail('start postgres: ' . $Test::postgresql::errstr) unless $pgserv;

{
	my $pool_size = 5;
	my $connected = AE::cvt 1;
	my $cv_one = AE::cvt;
	my $cv_all = AE::cvt;
	my $cv_conn_first = AE::cv {$connected->send}; $cv_conn_first->begin;
	my $cv_conn_one   = AE::cv {$cv_one->send}; $cv_conn_one->begin for 1..$pool_size;
	my $cv_conn_last  = AE::cv {$cv_all->send}; $cv_conn_last->begin;
	my $conn_info = uri_to_conninfo($pgserv->uri);
	my $pool; $pool = AnyEvent::PostgreSQL->new(
		%{$conn_info},
		name            => 'test1',
		pool_size       => $pool_size,
		on_connfail     => sub { my $self = shift;
			$event = shift;
			diag "connection error: " . $event->{reason};
		},
		on_connect_first      => sub { my $self = shift;
			is($pool, $self,"pool passed as first arg to on_connect_first");
			$cv_conn_first->end;
		},
		on_connect_one  => sub { my $self = shift;
			is($self, $pool, "pool passed as first arg to on_connect_one");
			my $desc = shift;
			diag "connect_one desc: $desc";
			like($desc,qr/$conn_info->{host}.*$conn_info->{port}/, 'on_connect_one: descriptions contains host');
			like($desc,qr/$conn_info->{dbname}/, 'on_connect_one: descriptions contains database name');
			like($desc,qr/$conn_info->{login}/, 'on_connect_one: descriptions contains user name');
			$cv_conn_one->end;
		},
		on_connect_last  => sub { my $self = shift;
			is($self, $pool, "pool passed as first arg to on_connect_last");
			$cv_conn_last->end
		},
	);
	$pool->connect;
	my ($self, $event) = eval {$connected->recv;}; fail "connect_first: $@" if $@;
	($self, $event) = eval {$cv_one->recv;}; fail "connect_one: $@" if $@;
	($self, $event) = eval {$cv_all->recv;}; fail "connect_last $@" if $@;
	$pool->disconnect;
}

{
	my $pool_size = 5;
	my $connected = AE::cvt 1;
	my $disconnected = AE::cvt 3;
	my $conn_info = uri_to_conninfo($pgserv->uri);
	my $cnt_disconnected_one = 0;
	my $cnt_disconnected_first = 0;
	my $cnt_disconnected_last = 0;
	my $pool; $pool = AnyEvent::PostgreSQL->new(
		%{$conn_info},
		name            => 'test2',
		pool_size         => $pool_size,
		on_connfail       => sub {my $self = shift; diag 'connfail: ' . $event->{reason};},
		on_connect_last   => my $connected = AE::cvt,
		on_disconnect_one => sub{$cnt_disconnected_one ++},
		on_disconnect_first => sub{$cnt_disconnected_first ++},
		on_disconnect_last  => sub{$cnt_disconnected_last ++; $disconnected->(@_); },
	);
	#AE::log(error => "AnyEvent::PostgreSQL object created, call connect()");
	$pool->connect;
	my ($self, $event) = eval {$connected->recv;}; fail "connected: $@" if $@;
	$pgserv->stop;
	my ($self2, $reason) = eval {$disconnected->recv;}; fail "disconnected: $@" if $@;
	is($cnt_disconnected_last, 1, 'on_disconnect_last called once');
	is($cnt_disconnected_first, 1, 'on_disconnect_first called once');
	is($cnt_disconnected_one, $pool->pool_size, 'on_disconnect_first called for each connection in pool');
	$pool->disconnect;
	$pgserv->start;
}

{
	my $pool_size = 1;
	my $conn_info = uri_to_conninfo($pgserv->uri);
	my $pool; $pool = AnyEvent::PostgreSQL->new(
		%{$conn_info},
		name              => 'test3',
		pool_size         => $pool_size,
		#on_connfail       => sub { AE::log error => 'connfail: %s', $_[1]->{reason};},
		#on_connect_all    => sub { AE::log error => 'connect_all: %s', @_[1];},
		on_connect_one    => sub { AE::log error => 'connect_one %s', @_[1];},
		on_disconnect_one => sub { AE::log error => 'disconnect_one: %s', @_[1];},
	);
	#AE::log(error => "AnyEvent::PostgreSQL object created, call connect()");
	$pool->connect;
	my ($cb,$start,$stop);
	$start = sub {$cb = $stop; $pgserv->start;};
	$stop = sub {$cb = $start; $pgserv->stop;};
	$cb = $stop;
	my $t; $t = AE::timer 0.01, 10, sub { $cb->(); warn "Not T" unless $t };
	eval { (AE::cvt 6)->recv; };
}

done_testing;
