package AnyEvent::PostgreSQL;
our $VERSION = 0.01;

=head1 NAME

 AnyEvent::PostgreSQL - Async PostgreSQL connector for perl5 with convient interface


=head1 SYNOPSIS

	use AnyEvent;
	use AnyEvent::PostgreSQL;
	my $pool = AnyEvent::PostgreSQL->new(
		server            => '127.0.0.1:5432',
		dbname            => 'testdb',
		login             => 'PG_USER',
		password          => 'PG_PASS',
		timeout           => 2.0,
		pool_size         => 5,
		on_connect_first  => my $connected = AE::cv,
		on_disconect_last => sub { my $pool = shift;
			my $reason = shift;
			warn "No more connections in pool: $reason";
		},
		on_connfail       => sub { my $pool = shift;
			my $event = shift;
			warn "Connection failed: " . $event->{reason};
		},
	);

	$pool->connect;
	my ($self, $desc) = $connected->recv;
	warn "have at least one connection in pool: $desc";
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

use Data::Dumper;
use AnyEvent::Socket qw(parse_hostport);
use AnyEvent::Pg::Pool;
use Mouse;
use Time::HiRes qw(time);


has server             => (is => 'rw', required => 1);
has dbname             => (is => 'rw', default => '');
has login              => (is => 'rw');
has password           => (is => 'rw');
has on_connfail        => (is => 'rw');
has on_connect_first   => (is => 'rw');
has on_connect_one     => (is => 'rw');
has on_connect_last    => (is => 'rw');
has on_disconnect_one  => (is => 'rw');
has connect_timeout    => (is => 'rw', default => 1);
has _pool              => (is => 'rw', default => sub{ [] });
has pool_size          => (is => 'rw', default => 5);
has _connect_cnt       => (is => 'rw');
has _conn_ok           => (is => 'rw', default => sub{ [] });


sub connect{ my $self = shift;
	$self->create_connectors;
	#$self->{query} = $self->{_pool}[0]->push_query(
	#	query     => 'SELECT 1',
	#	on_result => sub { AE::log error => 'QUERY RESULT CALLBACK: ' },
	#	on_error => sub { AE::log error => 'QUERY ERROR CALLBACK: ' },
	#);
	#$self->{_pool}->connect;
};

sub create_i_conector {
		my ($self, $i, $conn_info) = (shift, shift, shift);
		$self->{_conn_ok}[$i] = 0;
		$self->{_pool}[$i] = AnyEvent::Pg->new(
			$conn_info,
			timeout            => 2, # between network activity events
			on_connect         => sub {
				my $conn = shift;
				$self->{_connect_cnt} ++;
				$self->{_conn_ok}[$i] = 1;
				my $first_connect = $self->{_connect_cnt} == 1;
				my $last_connect = $self->{_connect_cnt} == $self->{pool_size};
				my $dbc = $conn->dbc;
				my $desc = sprintf('conn[%d] connected to %s:%s login:%s db:%s srv_ver:%s enc:%s',
					$i,
					(map {$dbc->$_//''} qw(host port user db)),
					$dbc->parameterStatus('server_version'),
					$dbc->parameterStatus('server_encoding'),
				);
				$self->{on_connect_one}->($self, $desc)   if $self->{on_connect_one};
				$self->{on_connect_first}->($self, $desc) if $self->{on_connect_first} && $first_connect;
				$self->{on_connect_last}->($self, $desc)  if $self->{on_connect_last} && $last_connect;
			},
			on_connect_error   => sub {
				my $conn = shift;
				(my $err = $conn->{dbc}->errorMessage) =~ s/[\n\s]+/ /gs;
				my $reason = "conn[$i]: $err";
				$self->create_i_conector($i, $conn_info);
				if ($self->{on_connfail}) {
					$self->{on_connfail}->($self, { on_conect_error_args => \@_, reason => $reason});
				}
			},
			on_error   => sub {
				my $conn = shift;
				my $fatal = shift; $fatal //= 0;
				(my $err = $conn->{dbc}->errorMessage) =~ s/[\n\s]+/ /gs;
				my $reason = "conn[$i]: $err";
				if ($fatal) {
					if ($self->{_conn_ok}[$i] ) {
						$self->create_i_conector($i, $conn_info);
						$self->{on_disconnect_one}->($self, $reason) if $self->{on_disconnect_one};
					} # skip else as it is handled in on_connect_error
				} else {
					#warn "on_error[$i]: $reason: " . Dumper \@_;
				}
			},
		);
}

sub create_connectors { my $self = shift;
	my ($host, $port) = parse_hostport($self->{server}, 5432);
	my $conn_info = {
		dbname          => $self->{dbname},
		user            => $self->{login},
		port            => $port,
		host            => $host,
		connect_timeout => $self->{connect_timeout},
	};
	for my $i (0 .. ($self->pool_size - 1)) {
		$self->create_i_conector($i, $conn_info);
	}
}

sub disconnect{ my $self = shift;
	$self->{_pool} = [];
	#for my $conn (@{$self->_pool}) {
	#	$conn->dbc->finish;
	#}
}

__PACKAGE__->meta->make_immutable();
1;
