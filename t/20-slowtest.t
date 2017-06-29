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

#use Devel::FindRef;
#{
#	my $pool;
#	{
#		my $pool_size = 1;
#		my $conn_info = uri_to_conninfo($pgserv->uri);
#		#my $disconnected = AE::cvt 1;
#		$pool = AnyEvent::PostgreSQL->new(
#			%{$conn_info},
#			name               => 'test_reconnect',
#			pool_size          => $pool_size,
#			on_connfail        => sub {diag sptintf('connfail: %s', $_[0]->{reason})},
#			on_connect_last    => (my $connected = AE::cvt 1),
#			on_disconnect_last => (my $disconnected = AE::cvt 1),
#		);
#		$pool->connect;
#		my ($desc) = eval {$connected->recv; }; fail "connect fail: $@" if $@;
#		like($desc,qr/127.0.0.1/, 'connect_last description have host mentioned');
#		#AE::log error => 'connected: %s', $desc;
#		$pool->disconnect;
#		($desc) = eval {$disconnected->recv; }; fail "disconnect fail: $@" if $@;
#		like($desc,qr/127.0.0.1/, 'disconnect_last description have host mentioned');
#		#AE::log error => 'disconnected: %s', $desc;
#		#$pool->DESTROY;
#		%{$connected} = ();
#	}
#	warn "!!!!!!!!!!!!!!!" .Devel::FindRef::track \$pool;
#	#@references = Devel::FindRef::find \$pool;
#	#for my $item (@references) {
#	#	my $ref = Devel::FindRef::ptr2ref($item->[1]);
#	#	warn $ref;
#	#}
#}
#diag "At this point \$pool should be destroyed";
##ok 1;

{
	my $pool_size = 1;
	my $conn_info = uri_to_conninfo($pgserv->uri);
	my $t;
	my ($cnt_connect, $cnt_disconnect) = (0,0);
	my $cv = AE::cvt 60;
	my $pool; $pool = AnyEvent::PostgreSQL->new(
		%{$conn_info},
		name              => 'test3_reconnect',
		pool_size         => $pool_size,
		on_connect_one    => sub { my $desc = shift;
			diag sprintf('connect_one %s', $desc) if $ENV{TEST_VERBOSE}//0 > 0;
			$cnt_connect++;
			$t = AE::timer 0.05, 0, sub { undef $t; $pgserv->stop; }
		},
		on_disconnect_one => sub { my $desc = shift;
			diag sprintf('disconnect_one: %s', $desc) if $ENV{TEST_VERBOSE}//0 > 0;
			$cv->send unless ++ $cnt_disconnect < 3;
			$t = AE::timer 0.05, 0, sub { undef $t; $pgserv->start; }
		},
	);
	#AE::log(error => "AnyEvent::PostgreSQL object created, call connect()");
	$pool->connect;
	$cv->recv;
	is($cnt_connect, 3, 'connect_one calles 3 times');
	is($cnt_disconnect, 3, 'disconnect_one calles 3 times');
}
done_testing;
