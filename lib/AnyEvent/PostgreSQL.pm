package AnyEvent::PostgreSQL;
our $VERSION = 0.02;

=head1 NAME

 AnyEvent::PostgreSQL - Async PostgreSQL connector for perl5 with convient interface


=head1 SYNOPSIS

	use AnyEvent;
	use AnyEvent::PostgreSQL;
	my $pool = AnyEvent::PostgreSQL->new(
		conn_info => {
			hostaddr        => '127.0.0.1',
			port            => 5432,
			dbname          => 'testdb',
			user            => 'PG_USER',
			password        => 'PG_PASS',
		},
		timeout           => 2.0,
		pool_size         => 5,
		on_connect_first  => my $connected = AE::cv,
		on_disconect_last => sub {
			my $reason = shift;
			warn "No more connections in pool: $reason";
		},
		on_connfail       => sub {
			my $event = shift;
			warn "Connection failed: " . $event->{reason};
		},
	);

	$pool->connect;
	my ($desc) = $connected->recv;
	warn "have at least one connection in pool: $desc";
	$pool->query([q{SELECT '$1':jsonb}, '{"key":"value"}'], sub {
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
#use AnyEvent::Socket qw(parse_hostport);
use AnyEvent::Pg::Pool;
use Mouse;
use Time::HiRes qw(time);
use Carp;
use Pg::PQ qw(:pgres);
#use Scalar::Util qw(weaken);
#use Guard;


has conn_info           => (is => 'rw', required => 1);
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
has name                => (is => 'rw', default => 'pgpool');
has _want_connect       => (is => 'rw', default => 0);

#has _guard              => (is => 'rw');
#sub BUILD { my $self = shift;
#	my $n=$self->{name};
#	$self->{_guard} = guard sub { warn  "AE:PostgreSQL guard: name:$n"};
#}


sub connect{ my $self = shift;
	return (0, "already connecting") if $self->{_want_connect};
	$self->{_want_connect} = 1;
	$self->create_connectors;
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
				$self->{on_connect_one}->($desc) if $self->{on_connect_one};
				if ($first_connect) {
					$self->{on_connect_first}->($desc) if $self->{on_connect_first};
				}
				if ($last_connect) {
					$self->{on_connect_last}->($desc) if $self->{on_connect_last};
				}
			},
			on_connect_error   => sub {
				my $conn = shift;
				(my $err = $conn->{dbc}->errorMessage) =~ s/[\n\s]+/ /gs;
				my $reason = "conn[$i]: $err";
				$self->create_i_conector($i, $conn_info) if $self->{_want_connect};
				if ($self->{on_connfail}) {
					$self->{on_connfail}->({reason => $reason});
				}
			},
			on_error   => sub {
				my $conn = shift;
				my $fatal = shift; $fatal //= 0;
				(my $err = $conn->{dbc}->errorMessage) =~ s/[\n\s]+/ /gs;
				my $reason = "conn[$i]: $err";
				if ($fatal) {
					if ($self->{_conn_ok}[$i]) { #disconnect
						#$self->{_conn_ok}[$i] = 0;
						my $last_disconnect = $self->{_connect_cnt} == 1;
						my $first_disconnect = $self->{_connect_cnt} == $self->{pool_size};
						$self->{_connect_cnt} --;
						$self->{on_disconnect_one}->($reason) if $self->{on_disconnect_one};
						if ($first_disconnect && $self->{on_disconnect_first}) {
							$self->{on_disconnect_first}->($reason) ;
						}
						if ($last_disconnect){
							$self->_clear_state;
							$self->{on_disconnect_last}->($reason) if $self->{on_disconnect_last};
						}
						if ($self->{_want_connect}) {
							$self->create_i_conector($i, $conn_info);
						}
					} # skip else as it is handled in on_connect_error
				} else {
					#warn "on_error[$i]: $reason: " . Dumper \@_;
				}
			},
		);
}

sub create_connectors { my $self = shift;
	my $conn_info = {
		%{$self->{conn_info}},
		connect_timeout => $self->{connect_timeout},
	};
	$conn_info->{host}//= $conn_info->{hostaddr};
	for (my $i = 0; $i < $self->pool_size; $i++) {
		$self->create_i_conector($i, $conn_info);
	}
}

sub disconnect{ my $self = shift;
	$self->{_want_connect} = 0;
	for my $conn (@{$self->_pool}) {
		$conn->abort_all if $conn;
	}
	$self->_clear_state;
}

sub push_query { my $self = shift;
	my $query = shift or croak 'need query';
	my $cb = pop or croak 'Need callback';
	my @available = grep {$_->queue_size() < 3} @{$self->{_pool}};
	#if (@available == 0){
	#	AE::postpone { $cb->({error => 1, reason => 'all connections busy'})};
	#	return;
	#}
	my $conn = @available[rand 0+@available];
	my %state;
	my $res = {error => 0, fatal => 0, result => []};
	$state{query} = $conn->push_query(
		query     => $query,
		on_error  => sub {
			my $conn = shift;
			(my $err = $conn->{dbc}->errorMessage) =~ s/[\n\s]+/ /gs;
			$res->{error} = 1; $res->{reason} = $err;
			#warn "on_error: " . Dumper \@_;
		},
		on_result => sub { my $conn = shift;
			my $pgres = shift;
			my $status = $pgres->status;
			if ($status == PGRES_FATAL_ERROR) {
				$res->{error} = 1; $res->{fatal} = 1;
				#$res->{reason} = $pgres->errorMessage;
				$res->{reason} = $pgres->errorField('message_primary');
				#$res->{reason} = $pgres->errorDescription;
			} elsif ($status == PGRES_COMMAND_OK || $status == PGRES_TUPLES_OK) {
				push @{$res->{result}}, $pgres;
			} else {
				$res->{error} = 1;
				$res->{reason} = $pgres->errorField('message_primary');
			}
			#warn "on_result " . Dumper \$pgres;
		},
		on_done   => sub { my $conn = shift;
			return unless %state; %state = ();
			#warn "on_done " . Dumper \@_;
			$cb->($res);
		},
	);
}

sub _clear_state{ my $self = shift;
	$self->{_pool} = [];
}

sub DEMOLISH { my $self = shift or return;
	#warn $self->{name} . " AE::PostgreSQL DEMOLISH";
	$self->_clear_state;
	#delete $self->{$_} for qw(on_connect_first on_connect_last on_connect_one);
}

__PACKAGE__->meta->make_immutable();
1;
