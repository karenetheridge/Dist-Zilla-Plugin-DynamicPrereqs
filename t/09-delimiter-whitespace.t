use strict;
use warnings;

use Test::More 0.88;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Path::Tiny;

use lib 't/lib';
use Helper;

use Test::File::ShareDir
    -share => { -module => { 'Dist::Zilla::Plugin::DynamicPrereqs' => 'share/DynamicPrereqs' } };

my $tzil = Builder->from_config(
    { dist_root => 'does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ MakeMaker => ],
            ) . <<'END_INI',

[DynamicPrereqs]
-delimiter = |
-raw = |$WriteMakefileArgs{PREREQ_PM}{'Test::More'} = $FallbackPrereqs{'Test::More'} = '0.123'
-raw = |    if eval { require Test::More; 1 };
END_INI
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
unlike($makefile, qr/[^\S\n]\n/, 'no trailing whitespace in modified file');

my $version = Dist::Zilla::Plugin::DynamicPrereqs->VERSION;
isnt(
    index(
        $makefile,
        <<CONTENT),
# inserted by Dist::Zilla::Plugin::DynamicPrereqs $version
\$WriteMakefileArgs{PREREQ_PM}{'Test::More'} = \$FallbackPrereqs{'Test::More'} = '0.123'
    if eval { require Test::More; 1 };

CONTENT
    -1,
    'code inserted into Makefile.PL generated by [MakeMaker], with whitespace intact',
) or diag "found Makefile.PL content:\n", $makefile;

run_makemaker($tzil);

diag 'got log messages: ', explain $tzil->log_messages
    if not Test::Builder->new->is_passing;

done_testing;
