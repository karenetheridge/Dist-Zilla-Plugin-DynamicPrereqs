use strict;
use warnings;

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Path::Tiny;
use PadWalker 'closed_over';
use Module::Runtime qw(use_module module_notional_filename);
use ExtUtils::MakeMaker;
use Dist::Zilla::Plugin::DynamicPrereqs;

use Test::File::ShareDir
    -share => { -module => { 'Dist::Zilla::Plugin::DynamicPrereqs' => 'share/DynamicPrereqs' } };

my $sub_prereqs = closed_over(\&Dist::Zilla::Plugin::DynamicPrereqs::register_prereqs)->{'%sub_prereqs'};
my %loaded_subs;

sub load_sub
{
    foreach my $sub (Dist::Zilla::Plugin::DynamicPrereqs->_all_required_subs_for(@_))
    {
        next if exists $loaded_subs{$sub};

        foreach my $prereq (keys %{$sub_prereqs->{$sub}})
        {
            note "loading $prereq $sub_prereqs->{$sub}{$prereq}";
            use_module($prereq, $sub_prereqs->{$sub}{$prereq});
        }

        my $filename = path(File::ShareDir::module_dir('Dist::Zilla::Plugin::DynamicPrereqs'), 'include_subs')->child($sub);
        note "loading $filename";
        do $filename;
        die $@ if $@;
        ++$loaded_subs{$sub};
    }
}

{
    load_sub('has_module');

    {
        # pick something we know is available, but not something we have loaded
        my $module = 'CPAN';

        ok(!exists($INC{module_notional_filename($module)}), "$module has not already been loaded");
        my $got_version;
        ok($got_version = has_module($module), "$module is installed; returned something true");
        is(has_module($module, '0'), 1, "$module is installed at least version 0");
        ok(!exists($INC{module_notional_filename($module)}), "$module has not been loaded by has_module()");

        require CPAN;
        is($got_version, MM->parse_version($INC{'CPAN.pm'}), 'has_version returned $CPAN::VERSION');
    }

    {
        my $module = 'Bloop::Blorp';
        ok(!exists($INC{module_notional_filename($module)}), "$module has not already been loaded");
        is(has_module($module), undef, "$module is not installed");
        ok(!exists($INC{module_notional_filename($module)}), "$module has not been loaded by has_module()");
    }

    {
        my $module = 'Dist::Zilla::Plugin::DynamicPrereqs';
        ok(exists($INC{module_notional_filename($module)}), "$module has already been loaded");
        is(has_module($module), $module->VERSION, "$module is installed; returned its version");
        is(has_module($module, '0'), 1, "$module is installed at least version 0");
        is(has_module($module, $module->VERSION), 1, "$module is installed at least version " . $module->VERSION);
    }
}

done_testing;
