use strict;
use warnings;

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Path::Tiny;
use Test::Deep;
use Dist::Zilla::Plugin::DynamicPrereqs;

# this time, we use our real sub definitions
use Test::File::ShareDir
    -share => { -module => { 'Dist::Zilla::Plugin::DynamicPrereqs' => 'share/DynamicPrereqs' } };

use lib 't/lib';
use Helper;

my @subs = sort
    grep { !/^\./ }
    map { $_->basename }
    path(File::ShareDir::module_dir('Dist::Zilla::Plugin::DynamicPrereqs'), 'include_subs')->children;

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ MakeMaker => ],
                [ DynamicPrereqs => { -include_sub => \@subs } ],
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

cmp_deeply(
    $tzil->distmeta,
    superhashof({
        dynamic_config => 1,
        prereqs => {
            configure => {
                requires => {
                    'ExtUtils::MakeMaker' => ignore,
                    'ExtUtils::CBuilder' => '0.27',
                    'Config' => '0',
                    'File::Spec' => 0,
                    'File::Temp' => '0',
                    'Text::ParseWords' => '0',
                },
            },
        },
    }),
    'added prereqs used by included subs',
)
or diag "found metadata:", explain $tzil->distmeta;

my $file = $build_dir->child('Makefile.PL');
ok(-e $file, 'Makefile.PL created');

my $makefile = $file->slurp_utf8;
unlike($makefile, qr/[^\S\n]\n/m, 'no trailing whitespace in modified file');
unlike($makefile, qr/\t/m, 'no tabs in modified file');

isnt(
    index($makefile, "sub $_ {\n"),
    -1,
    "Makefile.PL contains definition for $_()",
) foreach @subs;

run_makemaker($tzil);

{
    no strict 'refs';
    cmp_deeply(
        \%{'main::MyTestMakeMaker::'},
        superhashof({
            map {; $_ => *{"MyTestMakeMaker::$_"} } @subs
        }),
        'Makefile.PL defined all required subroutines',
    ) or diag 'Makefile.PL defined symbols: ', explain \%{'main::MyTestMakeMaker::'};
}

diag 'got log messages: ', explain $tzil->log_messages
    if not Test::Builder->new->is_passing;

done_testing;
