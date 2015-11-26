use Plack::Middleware::DBGp (
    komodo_debug_client_path => $ENV{REMOTE_DEBUGGER},
    remote_host              => "localhost:" . ($ENV{DEBUGGER_PORT} // 9000),
);
use Plack::Builder;
use Plack::Request;

my $app = sub {
    my ($env) = @_;
    my $req = Plack::Request->new($env);
    my $name = $req->parameters->{name} // 'world';

    return [ 200, [], ["Hello, ", $name] ]; 
};

builder {
    enable "DBGp";
    $app;
}
