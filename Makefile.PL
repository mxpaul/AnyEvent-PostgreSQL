use 5.008008;
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME              => 'AnyEvent::PostgreSQL',
	AUTHOR            => 'Author <mmonk@cpan.org>',
	VERSION_FROM      => 'lib/AnyEvent/PostgreSQL.pm',
	ABSTRACT_FROM     => 'lib/AnyEvent/PostgreSQL.pm',
	CONFIGURE_REQUIRES => {
		'ExtUtils::MakeMaker' => 0,
	},
	PREREQ_PM         => {
		'AnyEvent'           => 0,
		'AnyEvent::Pg::Pool' => 0,
		'Time::HiRes'        => 0,
		'Carp'               => 0,
		'Data::Dumper'       => 0,
		'Mouse'              => 0,
		'FindBin'            => 0,
	},
	TEST_REQUIRES         => {
		'Test::Harness'    => 0,
		'Test::More'       => 0,
		'Test::Deep'       => 0,
		'Test::PostgreSQL' => 0,
		'DBI'              => 0,
		'DBD::Pg'          => 0,
		'Exporter'         => 0,
		'use URI'          => 0,
	},
	#LIBS              => ['-lcares19', '-lcares'],
	#DEFINE            => '-g -ggdb -O0',
	#CONFIGURE => sub {
	#	require EV::MakeMaker;
	#	return {EV::MakeMaker::ev_args(
	#		INC               => '-I/usr/include/c-ares19 -I. -I./evcnn/src -I./xstnt -I./xsmy',
	#	)};
	#},
);
