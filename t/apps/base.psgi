use Plack::Middleware::DBGp (
    komodo_debug_client_path => $ENV{REMOTE_DEBUGGER},
    remote_host              => "localhost:" . ($ENV{DEBUGGER_PORT} // 9000),
);
use lib 't/apps/lib';
use Plack::Builder;
use App::Base;

builder {
    enable "DBGp";
    \&App::Base::app;
}
