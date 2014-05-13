use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Path::Tiny;
use File::pushd 'pushd';
use Test::Deep;
use Test::Deep::JSON;

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ MetaJSON => ],
                [ Prereqs => { 'strict' => '0', 'Test::More' => '0' } ],
                [ MakeMaker => ],
                [ DynamicPrereqs => 'Test::More' => {
                        raw => [
                            q|$WriteMakefileArgs{PREREQ_PM}{'Test::More'} = $FallbackPrereqs{'Test::More'} = '0.123'|,
                            q|if eval { require Test::More; 1 };|,
                        ],
                    },
                ],
                [ DynamicPrereqs => 'strict' => {
                        raw => [
                            q|$WriteMakefileArgs{PREREQ_PM}{'strict'} = $FallbackPrereqs{''} = '0.001'|,
                            q|if eval { require strict; 1 };|,
                        ],
                    },
                ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

$tzil->chrome->logger->set_debug(1);
is(
    exception { $tzil->build },
    undef,
    'build proceeds normally',
) or diag 'got log messages: ', explain $tzil->log_messages;

my $build_dir = path($tzil->tempdir)->child('build');

my $file = $build_dir->child('Makefile.PL');
ok(-e $file, 'Makefile.PL created');

my $makefile = $file->slurp_utf8;
unlike($makefile, qr/[^\S\n]\n/m, 'no trailing whitespace in modified file');

isnt(
    index(
        $makefile,
        "\n\n"
        . q|$WriteMakefileArgs{PREREQ_PM}{'Test::More'} = $FallbackPrereqs{'Test::More'} = '0.123'|
        . "\n"
        . q|if eval { require Test::More; 1 };|
        . "\n\n"
        . q|$WriteMakefileArgs{PREREQ_PM}{'strict'} = $FallbackPrereqs{'strict'} = '0.001'|
        . "\n"
        . q|if eval { require strict; 1 };|
        . "\n\n"
    )
    -1,
    'code inserted into Makefile.PL from both plugins',
) or diag "found Makefile.PL content:\n", $makefile;

{
    my $wd = pushd $build_dir;
    $tzil->plugin_named('MakeMaker')->build;
}

my $mymeta_json = $build_dir->child('MYMETA.json')->slurp_raw;
cmp_deeply(
    $mymeta_json,
    json(superhashof({
        dynamic_config => 0,
        prereqs => {
            configure => {
                requires => {
                    'ExtUtils::MakeMaker' => ignore,
                },
            },
            runtime => {
                requires => {
                    'strict' => '0.001',
                    'Test::More' => '0.123',
                },
            },
            build => ignore,    # always added by EUMM?
            test => ignore,     # always added by EUMM?
        },
    })),
    'dynamic_config reset to 0 in MYMETA; dynamic prereqs have been added from both plugins',
)
or diag "found MYMETA.json content:\n", $mymeta_json;

done_testing;
