use Plack::Middleware::DBGp (
    komodo_debug_client_path => $ENV{REMOTE_DEBUGGER},
    remote_host              => "localhost:" . ($ENV{DEBUGGER_PORT} // 9000),
    autostart                => 0,
    ide_key                  => 'dbgp_test',
);
use Plack::Builder;

my $app = sub {
    my ($env) = @_;

    return [ 200, [], ["Enabled: ", DB::isConnected() || 0] ];
};

builder {
    enable "DBGp";
    $app;
}
