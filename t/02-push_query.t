#!/usr/bin/env perl
use FindBin qw($Bin);
use lib ("$Bin/../lib", "$Bin/lib");
use Test::More;

use Test::AE; # AE::cvt
use Test::Helper;

use Test::PostgreSQL;
use Data::Dumper;
#use Devel::Leak;
use DBI;
use Carp;
use Test::Deep;


use AnyEvent::PostgreSQL;

sub setup_postgres_db {
	my $pgserv = shift or croak 'Need PostgreSQL dsn';
	eval {
		use strict;
		use warnings;
		my $dbh = DBI->connect($pgserv->dsn, undef, undef, {RaiseError => 1, AutoCommit => 1});
		my $sth = 'CREATE SEQUENCE seq_test';
		my $rv  = $dbh->do($sth);
		$sth = "CREATE TABLE test (id integer primary key DEFAULT nextval('seq_test'), data text)";
		$rv  = $dbh->do($sth);
		$sth = 'insert INTO test (data) VALUES (?)';
		my $test_data = '{"test": "data"}';
		$rv  = $dbh->do($sth, undef, $test_data);
		$sth = 'select * FROM test LIMIT 1';
		$rv  = $dbh->do($sth, undef);
		my $hash_ref = $dbh->selectrow_hashref($sth);
		cmp_deeply($hash_ref, {id => 1, data => $test_data});
	}; return (0, "db setup error: $@") if $@;
	return 1;
}

my $pgserv = Test::PostgreSQL->new();
BAIL_OUT('Can not start PostgreSQL server: ' . $Test::postgresql::errstr) unless $pgserv;
my $conn_info = uri_to_conninfo($pgserv->uri);
my ($success, $err) = setup_postgres_db($pgserv);
ok($success) or BAIL_OUT "setup_postgres_db: $err";

{
	my $pool; $pool = AnyEvent::PostgreSQL->new(
		conn_info         => $conn_info,
		name              => 'AEPQ',
		on_connfail       => sub {$event = shift; diag "connfail: " . $event->{reason}; },
		on_connect_last   => my $connected = AE::cvt,
		on_disconnect_one => sub {$event = shift; diag "disconnect: " . $event->{reason}; },
	);
	$pool->connect; $connected->recv;

	my $query = [q{select * from test where id = $1}, 1];
	$pool->push_query($query, my $done = AE::cvt);
	my ($res, @rest) = $done->recv;
	cmp_deeply($res, superhashof({error => 0, result => ignore() }), 'push_query select success');
	#diag 'Result array: ' . Dumper $res->{result};
	my $PgRes = $res->{result}[0];
	is($PgRes->status(), Pg::PQ::PGRES_TUPLES_OK, 'select returns tuples') or diag $PgRes->errorMessage;
}

{
	my $pool; $pool = AnyEvent::PostgreSQL->new(
		conn_info         => $conn_info,
		name              => 'AEPQ',
		on_connfail       => sub {$event = shift; diag "connfail: " . $event->{reason}; },
		on_connect_last   => my $connected = AE::cvt,
		on_disconnect_one => sub {$event = shift; diag "disconnect: " . $event->{reason}; },
	);
	$pool->connect; $connected->recv;

	my $query_syntax_error = [q{select * fORm test where id = $1}, 1];
	$pool->push_query($query_syntax_error, my $done = AE::cvt);
	my ($res, @rest) = $done->recv;
	my $expected_response = superhashof({error => 1, fatal => 1, reason => re(qr/syntax.*fORm/)});
	cmp_deeply($res, $expected_response, 'push_query select fatal error due to syntax error')
		or diag Dumper $res;
	#diag 'Result array: ' . Dumper $res->{result};
}

{
	my $pool; $pool = AnyEvent::PostgreSQL->new(
		conn_info         => $conn_info,
		name              => 'AEPQ',
		on_connfail       => sub {$event = shift; diag "connfail: " . $event->{reason}; },
		on_connect_last   => my $connected = AE::cvt,
		on_disconnect_one => sub {$event = shift; diag "disconnect: " . $event->{reason}; },
	);
	$pool->connect; $connected->recv;

	my $test_data = 'NEWTESTDATA';
	my $query = [q{update test set data = $2 where id = $1}, 1, $test_data ];
	$pool->push_query($query, my $done = AE::cvt);
	my ($res, @rest) = $done->recv;
	my $expected_response = superhashof({error => 0, fatal => 0, result => ignore()});
	cmp_deeply($res, $expected_response, 'push_query select fatal error due to syntax error')
		or diag Dumper $res;
	#is($PgRes->status(), Pg::PQ::PGRES_TUPLES_OK, 'update returns') or diag $PgRes->errorMessage;
	#diag 'Result array: ' . Dumper $res->{result};
}

{
	my ($cnn_total, $query_per_cnn) = (4, 3);
	my $queue_capacity = $cnn_total * $query_per_cnn;
	my $pool; $pool = AnyEvent::PostgreSQL->new(
		conn_info         => $conn_info,
		name              => 'AEPQ',
		on_connfail       => sub {$event = shift; diag "connfail: " . $event->{reason}; },
		on_connect_last   => my $connected = AE::cvt,
		on_disconnect_one => sub {$event = shift; diag "disconnect: " . $event->{reason}; },
		pool_size         => $cnn_total,
		cnn_max_queue_len => $query_per_cnn,
	);
	$pool->connect; $connected->recv;

	my $query = [q{select * from test where id = $1}, 1];
	my $want = superhashof({error => 0, result => ignore()});
	my $cv = AE::cvt 5; $cv->begin;
	for my $i (1..$queue_capacity) {
		$cv->begin;
		my $cnn = $pool->available_connectors;
		ok(ref $cnn, "Connector reference available for query $i");
		$pool->push_query($query, sub { my $res = shift;
			cmp_deeply($res, $want, "push_query $i select success") or diag Dumper $res;
			$cv->end;
		});
	}
	$cv->begin;
	my $cnn = $pool->available_connectors;
	is($cnn, undef, "Connector reference = undef if all connectors busy");
	$pool->push_query($query, sub { my $res = shift;
		my $want = superhashof({error => 1, reason => re(qr/queue.*limit/)});
		cmp_deeply($res, $want, "push_query informs if there is no available connections")
			or diag Dumper $res;
		$cv->end;
	});
	$cv->end; $cv->recv;
}

done_testing;
