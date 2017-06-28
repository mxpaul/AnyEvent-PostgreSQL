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

my $pgserv = Test::PostgreSQL->new();
BAIL_OUT('Can not start PostgreSQL server: ' . $Test::postgresql::errstr) unless $pgserv;

{
	my $pool_size = 1;
	my $conn_info = uri_to_conninfo($pgserv->uri);
	#my $disconnected = AE::cvt 1;
	my $pool; $pool = AnyEvent::PostgreSQL->new(
		%{$conn_info},
		name               => 'test_reconnect',
		pool_size          => $pool_size,
		on_connfail        => sub {diag sptintf('connfail: %s', $_[1]->{reason})},
		on_connect_last    => (my $connected = AE::cvt 1),
		on_disconnect_last => (my $disconnected = AE::cvt 1),
	);
	$pool->connect;
	my ($self, $desc) = eval {$connected->recv; }; fail "connect fail: $@" if $@;
	AE::log error => 'connected: %s', $desc;
	$pool->disconnect;
	my ($self, $desc) = eval {$disconnected->recv; }; fail "disconnect fail: $@" if $@;
	AE::log error => 'disconnected: %s', $desc;
}
ok 1;
done_testing;
