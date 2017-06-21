use 5.008008;
use ExtUtils::MakeMaker;

WriteMakefile(
	NAME              => 'AnyEvent::PostgreSQL',
	AUTHOR            => 'Author <mmonk@cpan.org>',
	VERSION_FROM      => 'lib/AnyEvent/PostgreSQL.pm',
	ABSTRACT_FROM     => 'lib/AnyEvent/PostgreSQL.pm',
	PREREQ_PM         => {
		'AnyEvent::Pg::Pool' => 4,
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
