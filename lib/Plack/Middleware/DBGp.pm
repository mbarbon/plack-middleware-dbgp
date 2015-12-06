package Plack::Middleware::DBGp;

=head1 NAME

Plack::Middleware::DBGp - interactive debugging for Plack applications

=cut

use strict;
use warnings;

our $VERSION = '0.02';

use constant {
    DEBUG_SINGLE_STEP_ON        =>  0x20,
    DEBUG_USE_SUB_ADDRESS       =>  0x40,
    DEBUG_REPORT_GOTO           =>  0x80,
    DEBUG_ALL                   => 0x7ff,
};

use constant {
    DEBUG_OFF                   => 0x0,
    DEBUG_DEFAULT_FLAGS         => # 0x73f
        DEBUG_ALL & ~(DEBUG_USE_SUB_ADDRESS|DEBUG_REPORT_GOTO),
    DEBUG_PREPARE_FLAGS         => # 0x73c
        DEBUG_ALL & ~(DEBUG_USE_SUB_ADDRESS|DEBUG_REPORT_GOTO|DEBUG_SINGLE_STEP_ON),
};

our @ISA;

my ($autostart, $idekey, $cookie_expiration);

# Unable to connect to Unix socket: /var/run/dbgp/uwsgi (No such file or directory)
# Running program outside the debugger...
sub _trap_connection_warnings {
    return if $_[0] =~ /^Unable to connect to Unix socket: /;
    return if $_[0] =~ /^Unable to connect to remote host: /;
    return if $_[0] =~ /^Running program outside the debugger/;

    print STDERR $_[0];
}

sub import {
    my ($class, %args) = @_;

    $args{komodo_debug_client_path} //= do {
        require Devel::Debug::DBGp;

        Devel::Debug::DBGp->debugger_path;
    };

    $autostart = $args{autostart} // 1;
    $idekey = $args{ide_key};
    $cookie_expiration = $args{cookie_expiration} // 3600;

    my %options = (
          Xdebug         => 1,
          ConnectAtStart => ($args{debug_startup} ? 1 : 0),
        ( LogFile        => $args{log_path} ) x !!$args{log_path},
    );

    if (!$args{remote_host}) {
        for my $required (qw(user client_dir client_socket)) {
            $args{$required} // die "Parameter '$required' is mandatory unless 'remote_host' is used";
        }

        my $error;
        my ($user, $dbgp_client_dir) = @args{qw(user client_dir)};
        my $group = getgrnam($));
        if (-d $dbgp_client_dir) {
            my ($mode, $uid, $gid) = (stat($dbgp_client_dir))[2, 4, 5];
            my $user_id = getpwnam($user) // die "Can't retrieve the UID for $user";

            $error = sprintf "invalid UID %d, should be %d", $uid, $user_id
                unless $uid == $user_id;
            $error = sprintf "invalid GID %d, should be %d", $gid, $)
                unless $gid == $);
            $error = sprintf "invalid permissions bits %04o, should be 0770", $mode & 0777
                unless ($mode & 0777) == 0770;
        } else {
            $error = "directory not found";
        }

        if ($error) {
            print STDERR <<"EOT";
There was the following issue with the DBGp client directory '$dbgp_client_dir': $error

You can fix it by running:
\$ sudo sh -c 'rm -rf $dbgp_client_dir &&
      mkdir $dbgp_client_dir &&
      chmod 2770 $dbgp_client_dir &&
      chown $user:$group $dbgp_client_dir'
EOT
            exit 1;
        }

        $options{RemotePath} = $args{client_socket};
    } else {
        $options{RemotePort} = $args{remote_host};
    }

    $ENV{PERLDB_OPTS} =
        join " ", map +(sprintf "%s=%s", $_, $options{$_}),
                      sort keys %options;

    if ($args{enbugger}) {
        require Enbugger;

        Enbugger->load_source;
    }

    unshift @INC, $args{komodo_debug_client_path};
    {
        local $SIG{__WARN__} = \&_trap_connection_warnings;
        require 'perl5db.pl';
    }

    $^P = DEBUG_PREPARE_FLAGS;

    require Plack::Middleware;
    require Plack::Request;
    require Plack::Response;
    require Plack::Util;

    @ISA = qw(Plack::Middleware);
}

sub reopen_dbgp_connection {
    local $SIG{__WARN__} = \&_trap_connection_warnings;
    DB::connectOrReconnect();
    DB::enable() if DB::isConnected();
}

sub close_dbgp_connection {
    DB::answerLastContinuationCommand('stopped');
    DB::disconnect();
    DB::disable();
    # this works around uWSGI bug fixed by
    # https://github.com/unbit/uwsgi/commit/c6f61719106908b82ba2714fd9d2836fb1c27f22
    $^P = DEBUG_OFF;
}

sub call {
    my($self, $env) = @_;

    my ($stop_session, $start_session, $debug_idekey);
    if ($autostart) {
        $ENV{DBGP_IDEKEY} = $idekey if defined $idekey;

        reopen_dbgp_connection();
    } else {
        my $req = Plack::Request->new($env);
        my $params = $req->parameters;
        my $cookies = $req->cookies;
        my $debug;

        if (exists $params->{XDEBUG_SESSION_STOP}) {
            $stop_session = 1;
        } elsif (exists $params->{XDEBUG_SESSION_START}) {
            $debug_idekey = $params->{XDEBUG_SESSION_START};
            $debug = $start_session = 1;
        } elsif (exists $cookies->{XDEBUG_SESSION}) {
            $debug_idekey = $cookies->{XDEBUG_SESSION};
            $debug = 1;
        }

        if ($debug) {
            $ENV{DBGP_IDEKEY} = $debug_idekey;
            reopen_dbgp_connection();
        }
    }

    my $res = $self->app->($env);

    if ($start_session || $stop_session) {
        $res = Plack::Response->new(@$res);

        if ($start_session) {
            $res->cookies->{XDEBUG_SESSION} = {
                value   => $debug_idekey,
                expires => time + $cookie_expiration,
            };
        } elsif ($stop_session) {
            $res->cookies->{XDEBUG_SESSION} = {
                value   => undef,
                expires => time - 24 * 60 * 60,
            };
        }

        $res = $res->finalize;
    }

    Plack::Util::response_cb($res, sub {
        return sub {
            # use $_[0] to try to avoid a copy
            if (!defined $_[0] && DB::isConnected()) {
                close_dbgp_connection();
            }

            return $_[0];
        };
    });
}

1;
