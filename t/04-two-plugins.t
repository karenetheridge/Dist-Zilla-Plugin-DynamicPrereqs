use strict;
use warnings;

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Path::Tiny;
use Test::Deep;
use Test::Deep::JSON;

use lib 't/lib';
use Helper;

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ Prereqs => { 'strict' => '0', 'Test::More' => '0' } ],
                [ MakeMaker => ],
                [ DynamicPrereqs => 'Test::More' => {
                        -raw => [
                            q|$WriteMakefileArgs{PREREQ_PM}{'Test::More'} = $FallbackPrereqs{'Test::More'} = '0.123'|,
                            q|if eval { require Test::More; 1 };|,
                        ],
                    },
                ],
                [ DynamicPrereqs => 'strict' => {
                        -raw => [
                            q|$WriteMakefileArgs{PREREQ_PM}{'strict'} = $FallbackPrereqs{'strict'} = '0.001'|,
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

my $version = Dist::Zilla::Plugin::DynamicPrereqs->VERSION || '<self>';
isnt(
    index(
        $makefile,
        <<CONTENT),
# inserted by Dist::Zilla::Plugin::DynamicPrereqs $version
\$WriteMakefileArgs{PREREQ_PM}{'Test::More'} = \$FallbackPrereqs{'Test::More'} = '0.123'
if eval { require Test::More; 1 };

CONTENT
    -1,
    'code inserted into Makefile.PL from first plugin',
) or diag "found Makefile.PL content:\n", $makefile;

isnt(
    index(
        $makefile,
        <<CONTENT),
# inserted by Dist::Zilla::Plugin::DynamicPrereqs $version
\$WriteMakefileArgs{PREREQ_PM}{'strict'} = \$FallbackPrereqs{'strict'} = '0.001'
if eval { require strict; 1 };

CONTENT
    -1,
    'code inserted into Makefile.PL from second plugin',
) or diag "found Makefile.PL content:\n", $makefile;

run_makemaker($tzil);

my $mymeta_json = $build_dir->child('MYMETA.json')->slurp_raw;
cmp_deeply(
    $mymeta_json,
    json(superhashof({
        dynamic_config => 0,
        prereqs => subhashof({
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
            build => ignore,    # added by [MakeMaker]; removed if
            test => ignore,     # EUMM version <= 6.63_02
        }),
    })),
    'dynamic_config reset to 0 in MYMETA; dynamic prereqs have been added from both plugins',
)
or diag "found MYMETA.json content:\n", $mymeta_json,
    "found Makefile.PL content:\n", $makefile;

diag 'got log messages: ', explain $tzil->log_messages
    if not Test::Builder->new->is_passing;

done_testing;
