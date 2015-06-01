use strict;
use warnings;

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Path::Tiny;
use PadWalker 'closed_over';
use Module::Runtime qw(use_module module_notional_filename);
use Dist::Zilla::Plugin::DynamicPrereqs;

use Test::File::ShareDir
    -share => { -module => { 'Dist::Zilla::Plugin::DynamicPrereqs' => 'share/DynamicPrereqs' } };

my $sub_prereqs = closed_over(\&Dist::Zilla::Plugin::DynamicPrereqs::register_prereqs)->{'%sub_prereqs'};

sub load_sub
{
    my $sub = shift;
    my $filename = path(File::ShareDir::module_dir('Dist::Zilla::Plugin::DynamicPrereqs'), 'include_subs')->child($sub);
    note "loading $filename and " . join(', ', map { "$_ $sub_prereqs->{$sub}{$_}" } keys %{$sub_prereqs->{$sub}});
    use_module($_, $sub_prereqs->{$sub}{$_}) foreach keys %{$sub_prereqs->{$sub}};
    do $filename;
}

{
    load_sub('has_module');

    {
        # pick something we know is available, but not something we have loaded
        my $module = 'CPAN';
        ok(!exists($INC{module_notional_filename($module)}), "$module has not already been loaded");
        is(has_module($module), 1, "$module is installed");
        is(has_module($module, '0'), 1, "$module is installed at least version 0");
        ok(!exists($INC{module_notional_filename($module)}), "$module has not been loaded by has_module()");
    }

    {
        my $module = 'Bloop::Blorp';
        ok(!exists($INC{module_notional_filename($module)}), "$module has not already been loaded");
        is(has_module($module), 0, "$module is not installed");
        ok(!exists($INC{module_notional_filename($module)}), "$module has not been loaded by has_module()");
    }

    {
        my $module = 'Dist::Zilla::Plugin::DynamicPrereqs';
        ok(exists($INC{module_notional_filename($module)}), "$module has already been loaded");
        is(has_module($module), 1, "$module is installed");
        is(has_module($module, '0'), 1, "$module is installed at least version 0");
        is(has_module($module, $module->VERSION), 1, "$module is installed at least version " . $module->VERSION);
    }
}

done_testing;