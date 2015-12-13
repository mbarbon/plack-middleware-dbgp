use Plack::Middleware::DBGp (
    debug_client_path        => $ENV{REMOTE_DEBUGGER},
    remote_host              => "localhost:" . ($ENV{DEBUGGER_PORT} // 9000),
    enbugger                 => 1,
);
use Plack::Builder;

my $app = sub {
    my ($env) = @_;

    return [ 200, [], ["Hello, world"] ];
};

builder {
    enable "DBGp";
    $app;
}
