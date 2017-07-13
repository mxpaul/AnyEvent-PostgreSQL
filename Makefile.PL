use 5.008008;
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME              => 'AnyEvent::PostgreSQL',
	AUTHOR            => 'Author <mmonk@cpan.org>',
	VERSION_FROM      => 'lib/AnyEvent/PostgreSQL.pm',
	ABSTRACT_FROM     => 'lib/AnyEvent/PostgreSQL.pm',
	BUILD_REQUIRES    => {
		'ExtUtils::MakeMaker' => 0,
	},
	TEST_REQUIRES     => {
		'Test::Harness'    => 0,
		'Test::More'       => 0,
		'FindBin'          => 0,
		'Test::PostgreSQL' => 0,
		'DBI'              => 0,
		'DBD::Pg'          => 0,
		'Test::Deep'       => 0,
		'Exporter'         => 0,
		'URI'              => 0,
	},
	PREREQ_PM         => {
		'Carp'             => 0,
		'Data::Dumper'     => 0,
		'Time::HiRes'      => 0,
		'AnyEvent'         => 0,
		'AnyEvent::Socket' => 0,
		'Pg::PQ'           => 0,
		'AnyEvent::Pg'     => 0,
		'Mouse'            => 0,
	},
	LICENSE           => 'GPL',
	#LIBS              => ['-lcares19', '-lcares'],
	#DEFINE            => '-g -ggdb -O0',
	#CONFIGURE => sub {
	#	require EV::MakeMaker;
	#	return {EV::MakeMaker::ev_args(
	#		INC               => '-I/usr/include/c-ares19 -I. -I./evcnn/src -I./xstnt -I./xsmy',
	#	)};
	#},
);
