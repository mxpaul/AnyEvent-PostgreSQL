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

my $pgserv = Test::PostgreSQL->new();
BAIL_OUT('Can not start PostgreSQL server: ' . $Test::postgresql::errstr) unless $pgserv;
my $conn_info = uri_to_conninfo($pgserv->uri);

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
		my $test_data = 'TEST TEST DATA';
		$rv  = $dbh->do($sth, undef, $test_data);
		$sth = 'select * FROM test LIMIT 1';
		$rv  = $dbh->do($sth, undef);
		my $hash_ref = $dbh->selectrow_hashref($sth);
		cmp_deeply($hash_ref, {id => 1, data => $test_data});
	}; return (0, "db setup error: $@") if $@;
	return 1;
}

{
	my $pool; $pool = AnyEvent::PostgreSQL->new(
		%{$conn_info},
		name              => 'AEPQ',
		on_connfail       => sub {$event = shift; diag "connfail: " . $event->{reason}; },
		on_connect_last   => my $connected = AE::cvt,
		on_disconnect_one => sub {$event = shift; diag "disconnect: " . $event->{reason}; },
	);
	$pool->connect; $connected->recv;
	my ($success, $err) = setup_postgres_db($pgserv);
	ok($success) or diag "setup_postgres_db: $err";

	my $query = {
		sql  => 'select * from test where id = ?',
		args => [1],
	};
	$pool->push_query($query, my $done = AE::cvt);
	my ($res, @rest) = $done->recv;
	cmp_deeply($res, superhashof({error => 0, result => ignore() }), 'push_query select success');
}

done_testing;
