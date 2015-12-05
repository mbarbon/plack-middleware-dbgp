#!/usr/bin/perl

use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
    module_name => 'Plack::Middleware::DBGp',
    license     => 'perl',
    requires    => {
        'Plack'         => '1.0031',
    },
    configure_requires => {
        'Module::Build' => 0.42,
    },
    test_requires => {
        'Test::Differences'         => 0,
        'XML::Parser'               => 0,
        'XML::Parser::EasyTree'     => 0,
        'HTTP::CookieJar'           => 0,
    },
);
$build->create_build_script;
