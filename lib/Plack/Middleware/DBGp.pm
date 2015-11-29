package Plack::Middleware::DBGp;

=head1 NAME

Plack::Middleware::DBGp - interactive debugging for Plack applications

=cut

use strict;
use warnings;

our $VERSION = '0.02';

use constant {
    DEBUG_SUB_ENTER_EXIT        =>   0x1,
    DEBUG_LINE_BY_LINE          =>   0x2,
    DEBUG_OPTIMIZATION_OFF      =>   0x4,
    DEBUG_PRESERVE_DATA         =>   0x8,
    DEBUG_SUB_DEFINITION_LINE   =>  0x10,
    DEBUG_SINGLE_STEP_ON        =>  0x20,
    DEBUG_USE_SUB_ADDRESS       =>  0x40,
    DEBUG_REPORT_GOTO           =>  0x80,
    DEBUG_EVAL_FILE_NAME        => 0x100,
    DEBUG_ANONSUB_FILE_NAME     => 0x200,
    DEBUG_SAVE_SOURCE_CODE      => 0x400,
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

my (%ORIG_DB_SUB, %DISABLED_DB_SUB);

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

    $args{komodo_debug_client_path} // die "Parameter 'komodo_debug_client_path' is mandatory";

    my $common_options = sprintf 'ConnectAtStart=%s Xdebug=1',
        ($args{debug_startup} ? 1 : 0);

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

        $ENV{PERLDB_OPTS} = sprintf 'RemotePath=%s %s', $args{client_socket}, $common_options;
    } else {
        $ENV{PERLDB_OPTS} = sprintf 'RemotePort=%s %s', $args{remote_host}, $common_options;
    }

    unshift @INC, $args{komodo_debug_client_path};
    {
        local $SIG{__WARN__} = \&_trap_connection_warnings;
        require 'perl5db.pl';
        %ORIG_DB_SUB = %DISABLED_DB_SUB = map {
            ($_ => *DB::sub{$_}) x !!*DB::sub{$_}
        } qw(CODE SCALAR ARRAY HASH);
        delete $DISABLED_DB_SUB{CODE};
    }
    $^P = DEBUG_PREPARE_FLAGS;

    require Plack::Middleware;
    require Plack::Util;

    @ISA = qw(Plack::Middleware);
}

sub reopen_dbgp_connection {
    local $SIG{__WARN__} = \&_trap_connection_warnings;
    DB::connectOrReconnect();
    _set_enabled(1) if DB::isConnected();
}

sub close_dbgp_connection {
    DB::answerLastContinuationCommand('stopped');
    DB::disconnect();
    _set_enabled(0);
    # this works around uWSGI bug fixed by
    # https://github.com/unbit/uwsgi/commit/c6f61719106908b82ba2714fd9d2836fb1c27f22
    $^P = DEBUG_OFF;
}

sub _set_enabled {
    if ($_[0]) {
        $DB::single = 1;
        $^P = DEBUG_DEFAULT_FLAGS;
        undef *DB::sub;
        *DB::sub = $ORIG_DB_SUB{$_} for keys %ORIG_DB_SUB;
    } else {
        $DB::single = 0;
        $^P = DEBUG_PREPARE_FLAGS;
        undef *DB::sub;
        *DB::sub = $DISABLED_DB_SUB{$_} for keys %DISABLED_DB_SUB;
    }
}

sub call {
    my($self, $env) = @_;

    reopen_dbgp_connection();

    my $res = $self->app->($env);

    Plack::Util::response_cb($res, sub {
        return sub {
            # use $_[0] to try to avoid a copy
            if (!defined $_[0]) {
                close_dbgp_connection();
            }

            return $_[0];
        };
    });
}

1;
