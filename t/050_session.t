#!/usr/bin/perl

use t::lib::Test;

start_listening();
run_app('t/apps/session.psgi');

send_request('/');
response_is('Enabled: 0', { value => undef });

send_request('/?XDEBUG_SESSION_START=test');
wait_connection();
command_is(['run'], {
    status  => 'stopped',
    command => 'run',
});
response_is('Enabled: 1', { value => 'XDEBUG_SESSION=test', expires => 3600 });

send_request('/', 'XDEBUG_SESSION=test');
wait_connection();
command_is(['run'], {
    status  => 'stopped',
    command => 'run',
});
response_is('Enabled: 1', { value => undef });

send_request('/?XDEBUG_SESSION_STOP=abcd');
response_is('Enabled: 0', { value => 'XDEBUG_SESSION=', expires => -1 });

send_request('/?XDEBUG_SESSION_STOP=abcd', 'XDEBUG_SESSION=test');
response_is('Enabled: 0', { value => 'XDEBUG_SESSION=', expires => -1 });

send_request('/?XDEBUG_SESSION_STOP=', 'XDEBUG_SESSION=test');
response_is('Enabled: 0', { value => 'XDEBUG_SESSION=', expires => -1 });

done_testing();
