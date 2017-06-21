#!perl -T
use 5.010;
use strict;
use warnings FATAL => 'all';

use Test::More;
plan tests => 1;
our $module;

BEGIN {
	$module = 'AnyEvent::PostgreSQL';
	use_ok($module) || print "Bail out!\n";
}

diag(sprintf("Testing $module %s, Perl %s, %s", $AnyEvent::PostgreSQL::VERSION, $], $^X));
