package AnyEvent::PostgreSQL;
our $VERSION = 0.01;

=head1 NAME

 AnyEvent::PostgreSQL - Async PostgreSQL connector for perl5 with convient interface


=head1 SYNOPSIS

	use AnyEvent;
	use AnyEvent::PostgreSQL;
	my $pool = AnyEvent::PostgreSQL->new(
		server        => '127.0.0.1:5432',
		dbname        => 'testdb',
		login         => 'PG_USER',
		password      => 'PG_PASS',
		timeout       => 2.0,
		pool_capacity => 2.0,
		on_connect => my $connected = AE::cv,
		on_disconect => sub {
		},
		on_connfail => sub {
		},
	);

	$pool->connect;
	my ($self) = $connected->recv;
	$pool->query(q{SELECT '{"key":"value"}':jsonb}, sub {
		my ($self, $result, $reason) = @_;
		if ($result) {
		} else {
			warn "SELECT error: $reason";
		}
	});

=head1 DESCRIPTION

AnyEvent::PostgreSQL - 15-th competing Postgres connector

=cut

1;
