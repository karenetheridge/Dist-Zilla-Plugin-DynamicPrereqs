use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Path::Tiny;

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ MetaJSON => ],
                [ Prereqs => { 'strict' => '0', 'Test::More' => '0' } ],
                [ DynamicPrereqs => {
                        raw => [
                            q|$WriteMakefileArgs{PREREQ_PM}{'Test::More'} = $FallbackPrereqs{'Test::More'} = '0.123'|,
                            q|if eval { require Test::More; 1 };|,
                        ],
                    },
                ],
                [ MakeMaker => ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

$tzil->chrome->logger->set_debug(1);
like(
    exception { $tzil->build },
    # as of Dist::Zilla 5.016, Makefile.PL is not created until [MakeMaker]
    # runs its setup_installer, so we will fail to find a file to munge. If
    # https://github.com/rjbs/Dist-Zilla/pull/229 ever gets merged, we will be
    # able to find a Makefile.PL but not find the adjacent code for munging.
    qr/(No Makefile.PL found!|failed to find position in Makefile.PL to munge!)/,
    'build aborts due to bad plugin ordering',
) or diag "log messages:\n", join("\n", @{ $tzil->log_messages });

done_testing;
