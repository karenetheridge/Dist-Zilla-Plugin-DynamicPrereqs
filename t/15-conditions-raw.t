use strict;
use warnings;

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Path::Tiny;

use Test::File::ShareDir
    -share => { -module => { 'Dist::Zilla::Plugin::DynamicPrereqs' => 'share/DynamicPrereqs' } };

use lib 't/lib';
use Helper;

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ MakeMaker => ],
                [ DynamicPrereqs => {
                        -condition => [
                            q|can_use('Test::More')|,
                            '1 == 2',
                        ],
                        -raw => [
                            q|$WriteMakefileArgs{PREREQ_PM}{'Test::More'} = $FallbackPrereqs{'Test::More'} = '0.123';|,
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

my $version = Dist::Zilla::Plugin::DynamicPrereqs->VERSION;
isnt(
    index(
        $makefile,
        <<CONTENT),
# inserted by Dist::Zilla::Plugin::DynamicPrereqs $version
if (can_use('Test::More') && 1 == 2) {
\$WriteMakefileArgs{PREREQ_PM}{'Test::More'} = \$FallbackPrereqs{'Test::More'} = '0.123';
}

CONTENT
    -1,
    'code inserted into Makefile.PL generated by [MakeMaker]',
) or diag "found Makefile.PL content:\n", $makefile;

my $expected_subs = <<CONTENT;

# inserted by Dist::Zilla::Plugin::DynamicPrereqs $version
__DEFINITION__
CONTENT

my $definition = path(File::ShareDir::module_dir('Dist::Zilla::Plugin::DynamicPrereqs'), 'include_subs', 'can_use')->slurp_utf8;
$expected_subs =~ s/__DEFINITION__\n/$definition/;

my $included_subs_index = index($makefile, $expected_subs);
isnt(
    $included_subs_index,
    -1,
    'sub referenced in conditional is inserted from sharedir files into Makefile.PL',
) or diag "found Makefile.PL content:\n", $makefile;

is(
    length($makefile),
    $included_subs_index + length($expected_subs),
    'included_subs appear at the very end of the file',
) or $included_subs_index != -1
    && diag 'found content after included subs: '
        . substr($makefile, $included_subs_index + length($expected_subs));


run_makemaker($tzil);

diag 'got log messages: ', explain $tzil->log_messages
    if not Test::Builder->new->is_passing;

done_testing;
