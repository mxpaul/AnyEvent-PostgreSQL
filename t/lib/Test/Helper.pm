package Test::Helper;

use Exporter 'import'; # gives you Exporter's import() method directly
our @EXPORT_OK = @EXPORT = qw(uri_to_conninfo);  # symbols to export on request

use URI;
use Carp;

sub uri_to_conninfo {
	my $uri = shift or croak 'Need uri';
	my $u = URI->new($uri);
	$u->scheme('http');
	my ($login, $password) = split(':', $u->userinfo);
	(my $dbname = $u->path) =~ s{/}{}g;
	{
		host          => $u->host(),
		port          => $u->port(),
		dbname        => $dbname,
		user          => $login,
		password      => $password//'',
	}
}

1;
