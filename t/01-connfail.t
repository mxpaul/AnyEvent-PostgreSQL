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

{
	my $addr = '127.0.0.1:28761';
	my $pool = AnyEvent::PostgreSQL->new(
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
}
#AE::log(error => "");
#AE::log(error => "Starting postgres");
my $pgserv = Test::PostgreSQL->new();
fail('start postgres: ' . $Test::postgresql::errstr) unless $pgserv;
#AE::log(error => "Postgres started with URI: %s", $pgserv->uri);

{
	my $pool_size = 5;
	my $connected = AE::cvt 1;
	my $cv_one = AE::cvt;
	my $cv_all = AE::cvt;
	my $cv_conn_first = AE::cv {$connected->send}; $cv_conn_first->begin;
	my $cv_conn_one = AE::cv {$cv_one->send}; $cv_conn_one->begin for 1..$pool_size;
	my $cv_conn_all = AE::cv {$cv_all->send}; $cv_conn_all->begin;
	my $pool; $pool = AnyEvent::PostgreSQL->new(
		%{uri_to_conninfo($pgserv->uri)},
		pool_size       => $pool_size,
		on_connfail     => sub {fail "connection should not fail"},
		on_connect      => sub { my $self = shift;
			is($pool, $self,"pool passed as first arg to on_connect");
			$cv_conn_first->end;
		},
		on_connect_one  => sub { my $self = shift;
			fail "pool passed as first arg to on_connect_one" unless $pool == $self;
			$cv_conn_one->end;
		},
		on_connect_all  => sub { my $self = shift;
			fail "pool passed as first arg to on_connect_all" unless $pool == $self;
			$cv_conn_all->end
		},
	);
	#AE::log(error => "AnyEvent::PostgreSQL object created, call connect()");
	$pool->connect;
	#AE::log(error => "AnyEvent::PostgreSQL connect() returned");
	my ($self, $event) = eval {$connected->recv;}; fail "connected: $@" if $@;
	($self, $event) = eval {$cv_one->recv;}; fail "connect_one: $@" if $@;
	($self, $event) = eval {$cv_all->recv;}; fail "connect_all $@" if $@;
	#AE::log(error => "on_connect fired");
	#is($self, $pool, 'pool object passed as first argument to connfail_callback');
}

done_testing;
