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

use AnyEvent;
use Data::Dumper;
use AnyEvent::Socket qw(parse_hostport);
use AnyEvent::Pg::Pool;
use Mouse;
use Time::HiRes qw(time);
use Scalar::Util qw(weaken);
use Guard;


has server              => (is => 'rw', required => 1);
has dbname              => (is => 'rw', default => '');
has login               => (is => 'rw');
has password            => (is => 'rw');
has on_connfail         => (is => 'rw', weak_ref => 0);
has on_connect_first    => (is => 'rw', weak_ref => 0);
has on_connect_one      => (is => 'rw', weak_ref => 0);
has on_connect_last     => (is => 'rw', weak_ref => 0);
has on_disconnect_one   => (is => 'rw', weak_ref => 0);
has on_disconnect_first => (is => 'rw', weak_ref => 0);
has on_disconnect_last  => (is => 'rw', weak_ref => 0);
has connect_timeout     => (is => 'rw', default => 1);
has _pool               => (is => 'rw', default => sub{ [] });
has pool_size           => (is => 'rw', default => 5);
has _connect_cnt        => (is => 'rw');
has _conn_ok            => (is => 'rw', default => sub{ [] });
#has _guard              => (is => 'rw');
has name                => (is => 'rw', default => 'noname');
has _want_connect       => (is => 'rw', default => 0);

sub BUILD { my $self = shift;
	my $n=$self->{name};
	#$self->{_guard} = guard sub { warn  "$n AE:PostgreSQL guard"};
}


sub connect{ my $self = shift;
	return (0, "already connecting") if $self->{_want_connect};
	$self->{_want_connect} = 1;
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
				my ($cb1, $cb2, $cb3);
				$cb1 = $self->{on_connect_one} and $cb1->($self, $desc);
				if ($first_connect) {
					$cb2 = $self->{on_connect_first} and $cb2->($self, $desc);
				}
				$cb3 = $self->{on_connect_last} and $cb3->($self, $desc) if $last_connect;
			},
			on_connect_error   => sub {
				my $conn = shift;
				(my $err = $conn->{dbc}->errorMessage) =~ s/[\n\s]+/ /gs;
				my $reason = "conn[$i]: $err";
				$self->create_i_conector($i, $conn_info) if $self->{_want_connect};
				if ($self->{on_connfail}) {
					$self->{on_connfail}->($self, {reason => $reason});
				}
			},
			on_error   => sub {
				my $conn = shift;
				my $fatal = shift; $fatal //= 0;
				(my $err = $conn->{dbc}->errorMessage) =~ s/[\n\s]+/ /gs;
				my $reason = "conn[$i]: $err";
				if ($fatal) {
					if ($self->{_conn_ok}[$i]) {
						my $last_disconnect = $self->{_connect_cnt} == 1;
						my $first_disconnect = $self->{_connect_cnt} == $self->{pool_size};
						$self->{_connect_cnt} --;
						if ($self->{_want_connect}) {
							$self->create_i_conector($i, $conn_info);
						}
						$self->{on_disconnect_one}->($self, $reason) if $self->{on_disconnect_one};
						if ($first_disconnect && $self->{on_disconnect_first}) {
							$self->{on_disconnect_first}->($self, $reason) ;
						}
						if ($last_disconnect){
							$self->_clear_state;
							$self->{on_disconnect_last}->($self, $reason) if $self->{on_disconnect_last};
						}
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
	$self->{_want_connect} = 0;
	for my $conn (@{$self->_pool}) {
		$conn->abort_all;
	}
	$self->_clear_state;
}

sub _clear_state{ my $self = shift;
	$self->{_pool} = [];
}

sub DEMOLISH { my $self = shift or return;
	#warn $self->{name} . " AE::PostgreSQL DEMOLISH";
	$self->_clear_state;
}

__PACKAGE__->meta->make_immutable();
1;
