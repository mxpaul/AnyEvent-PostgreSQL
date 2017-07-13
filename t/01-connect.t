#!/usr/bin/env perl
use FindBin qw($Bin);
use lib ("$Bin/../lib", "$Bin/lib");
use Test::More;
use Test::Deep;

use Test::AE; # AE::cvt
use Test::Helper;

use Test::PostgreSQL;
use Data::Dumper;
#use Devel::Leak;

use AnyEvent::PostgreSQL;

{
	#my $addr = '127.0.0.1:28761';
	my $conn_info = {
		hostaddr => '127.0.0.1',
		port     => 28761,
		dbname   => 'testdb',
		user     => 'PG_USER',
		password => 'PG_PASS',
		sslmode  => 'disable',
	};

	my $pool;
	$pool = AnyEvent::PostgreSQL->new(
		name            => 'wrongport',
		conn_info       => $conn_info,
		connect_timeout => 0.0001,
		on_connfail     => (my $connfail = AE::cvt),
	);
	cmp_deeply($pool->conn_info, $conn_info, 'conn_info structure kept in pool object');
	$pool->connect;

	my ($event) = eval {$connfail->recv;}; fail $@ if $@;
	is(ref $event, 'HASH', 'connfail returns event description as HASH');
	like($event->{reason}, qr/connection.+(fail|refuse).*127.0.0.1.*28761/i,
		'reason has descrpitive message after connection has failed with host and port identified');
	$pool->disconnect;
}

my $pgserv = Test::PostgreSQL->new();
BAIL_OUT('Can not start PostgreSQL server: ' . $Test::postgresql::errstr) unless $pgserv;

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
		conn_info   => $conn_info,
		name        => 'test1',
		pool_size   => $pool_size,
		on_connfail => sub {
			$event = shift;
			diag "connection error: " . $event->{reason};
		},
		on_connect_first => sub {$cv_conn_first->end;},
		on_connect_one   => sub {
			my $desc = shift;
			diag "connect_one desc: $desc";
			like($desc,qr/$conn_info->{host}.*$conn_info->{port}/, 'on_connect_one: descriptions contains host');
			like($desc,qr/$conn_info->{dbname}/, 'on_connect_one: descriptions contains database name');
			like($desc,qr/$conn_info->{login}/, 'on_connect_one: descriptions contains user name');
			$cv_conn_one->end;
		},
		on_connect_last  => sub {$cv_conn_last->end},
	);
	$pool->connect;
	my ($event) = eval {$connected->recv;}; fail "connect_first: $@" if $@;
	($event) = eval {$cv_one->recv;}; fail "connect_one: $@" if $@;
	($event) = eval {$cv_all->recv;}; fail "connect_last $@" if $@;
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
		conn_info           => $conn_info,
		name                => 'test2',
		pool_size           => $pool_size,
		on_connfail         => sub {my $event = shift; diag 'connfail: ' . $event->{reason};},
		on_connect_last     => my $connected = AE::cvt,
		on_disconnect_one   => sub{$cnt_disconnected_one ++},
		on_disconnect_first => sub{$cnt_disconnected_first ++},
		on_disconnect_last  => sub{$cnt_disconnected_last ++; $disconnected->(@_); },
	);
	#AE::log(error => "AnyEvent::PostgreSQL object created, call connect()");
	$pool->connect;
	my ($event) = eval {$connected->recv;}; fail "connected: $@" if $@;
	$pgserv->stop;
	my ($reason) = eval {$disconnected->recv;}; fail "disconnected: $@" if $@;
	is($cnt_disconnected_last, 1, 'on_disconnect_last called once');
	is($cnt_disconnected_first, 1, 'on_disconnect_first called once');
	is($cnt_disconnected_one, $pool->pool_size, 'on_disconnect_one called for each connection in pool');
	$pool->disconnect;
	$pgserv->start;
}

done_testing;
