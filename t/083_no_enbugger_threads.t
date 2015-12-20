#!/usr/bin/perl

use if do { require Config; !$Config::Config{usethreads} },
    'Test::More' => 'skip_all' => 'non-threaded Perl';
use t::lib::Test;

start_listening();
run_app('t/apps/enbugger.psgi');

send_request('/');
wait_connection();
command_is([qw(breakpoint_set -t line -f file://t/apps/enbugger.psgi -n 15)], {
    state   => 'enabled',
    id      => 0,
});
command_is(['run'], {
    status  => 'break',
    command => 'run',
});
command_is(['run'], {
    status  => 'stopped',
    command => 'run',
});
response_is('Hello, world');

done_testing();
