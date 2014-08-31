use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Path::Tiny;

{
    my $tzil = Builder->from_config(
        { dist_root => 't/does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    [ GatherDir => ],
                    [ MetaJSON => ],
                    [ Prereqs => { 'strict' => '0', 'Test::More' => '0' } ],
                    [ ModuleBuild => ],
                    [ DynamicPrereqs => {
                            raw => [
                                q|$WriteMakefileArgs{PREREQ_PM}{'Test::More'} = $FallbackPrereqs{'Test::More'} = '0.123'|,
                                q|if eval { require Test::More; 1 };|,
                            ],
                        },
                    ],
                ),
                path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
            },
        },
    );

    $tzil->chrome->logger->set_debug(1);
    like(
        exception { $tzil->build },
        qr/No Makefile.PL found!/,
        'only Makefile.PL supported at this time',
    );

    diag 'got log messages: ', explain $tzil->log_messages
        if not Test::Builder->new->is_passing;
}

{
    my $tzil = Builder->from_config(
        { dist_root => 't/does-not-exist' },
        {
            add_files => {
                path(qw(source dist.ini)) => simple_ini(
                    [ GatherDir => ],
                    [ MetaJSON => ],
                    [ Prereqs => { 'strict' => '0', 'Test::More' => '0' } ],
                    [ MakeMaker => ],
                    [ ModuleBuild => ],
                    [ DynamicPrereqs => {
                            raw => [
                                q|$WriteMakefileArgs{PREREQ_PM}{'Test::More'} = $FallbackPrereqs{'Test::More'} = '0.123'|,
                                q|if eval { require Test::More; 1 };|,
                            ],
                        },
                    ],
                ),
                path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
            },
        },
    );

    $tzil->chrome->logger->set_debug(1);
    like(
        exception { $tzil->build },
        qr/Build.PL detected - dynamic prereqs will not be added to it!/,
        'Makefile.PL and *only* Makefile.PL supported at this time',
    ) or diag 'got log messages: ', explain $tzil->log_messages;

    diag 'got log messages: ', explain $tzil->log_messages
        if not Test::Builder->new->is_passing;
}

done_testing;
