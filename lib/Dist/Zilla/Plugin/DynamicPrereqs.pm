use strict;
use warnings;
package Dist::Zilla::Plugin::DynamicPrereqs;
# ABSTRACT: Specify dynamic (user-side) prerequisites for your distribution
# KEYWORDS: plugin distribution metadata MYMETA prerequisites Makefile.PL dynamic
# vim: set ts=8 sw=4 tw=78 et :

our $VERSION = '0.011'; # TRIAL

use Moose;
with
    'Dist::Zilla::Role::InstallTool',
    'Dist::Zilla::Role::MetaProvider',
    'Dist::Zilla::Role::PrereqSource',
    'Dist::Zilla::Role::AfterBuild',
    'Dist::Zilla::Role::TextTemplate',
;
use List::Util 1.33 qw(first notall);
use Module::Runtime 'module_notional_filename';
use Try::Tiny;
use Path::Tiny;
use File::ShareDir;
use namespace::autoclean;
use feature 'state';

has raw => (
    isa => 'ArrayRef[Str]',
    traits => ['Array'],
    handles => { raw => 'elements' },
    lazy => 1,
    default => sub {
        my $self = shift;

        my @lines;
        if (my $filename = $self->raw_from_file)
        {
            my $file = first { $_->name eq $filename } @{ $self->zilla->files };
            $self->log_fatal([ 'no such file in build: %s' ], $filename) if not $file;
            $self->zilla->prune_file($file);
            try {
                @lines = split("\n", $file->content);
            }
            catch {
                $self->log_fatal($_);
            };
        }

        $self->log('no content found in -raw!') if not @lines;
        return \@lines;
    },
);

has raw_from_file => (
    is => 'ro', isa => 'Str',
);

has include_subs => (
    isa => 'ArrayRef[Str]',
    traits => ['Array'],
    handles => { include_subs => 'elements' },
    lazy => 1,
    default => sub { [] },
);

sub mvp_multivalue_args { qw(raw include_subs) }

sub mvp_aliases { +{
    '-raw' => 'raw',
    '-delimiter' => 'delimiter',
    '-raw_from_file' => 'raw_from_file',
    '-include_sub' => 'include_subs',
} }

around BUILDARGS => sub
{
    my $orig = shift;
    my $class = shift;

    my $args = $class->$orig(@_);

    my $delimiter = delete $args->{delimiter};
    if (defined $delimiter and length($delimiter))
    {
        s/^\Q$delimiter\E// foreach @{$args->{raw}};
    }

    return $args;
};

sub BUILD
{
    my ($self, $args) = @_;

    my %extra_args = %$args;
    delete @extra_args{ map { $_->name } $self->meta->get_all_attributes };
    if (my @keys = keys %extra_args)
    {
        $self->log('Warning: unrecognized argument' . (@keys > 1 ? 's' : '')
                . ' (' . join(', ', @keys) . ') passed. Perhaps you need to upgrade?');
    }
}

sub metadata { return +{ dynamic_config => 1 } }

sub after_build
{
    my $self = shift;
    $self->log_fatal('Build.PL detected - dynamic prereqs will not be added to it!')
        if first { $_->name eq 'Build.PL' } @{ $self->zilla->files };
}

sub setup_installer
{
    my $self = shift;

    $self->log_fatal('[MakeMaker::Awesome] must be at least version 0.19 to be used with [DynamicPrereqs]')
        if $INC{module_notional_filename('Dist::Zilla::Plugin::MakeMaker::Awesome')}
            and not eval { Dist::Zilla::Plugin::MakeMaker::Awesome->VERSION('0.19') };

    my $file = first { $_->name eq 'Makefile.PL' } @{$self->zilla->files};
    $self->log_fatal('No Makefile.PL found!') if not $file;

    my $content = $file->content;

    $self->log_debug('Inserting dynamic prereq into Makefile.PL...');

    # insert after declarations for BOTH %WriteMakefileArgs, %FallbackPrereqs.
    # TODO: if marker cannot be found, fall back to looking for just
    # %WriteMakefileArgs -- this requires modifying the content too.
    $self->log_fatal('failed to find position in Makefile.PL to munge!')
        if $content !~ m'^my %FallbackPrereqs = \((?:\n[^;]+^)?\);$'mg;

    my $pos = pos($content);

    $content = substr($content, 0, $pos)
        . "\n\n"
        . "# inserted by " . blessed($self) . ' ' . $self->VERSION . "\n"
        . join("\n", $self->raw)
        . "\n" . substr($content, $pos);

    $content =~ s/\n+\z/\n/;

    # track which subs have already been included by some other instance
    state %included_subs;

    if (my @include_subs = grep { not exists $included_subs{$_} } $self->_all_required_subs)
    {
        $content .= "\n# inserted by " . blessed($self) . ' ' . $self->VERSION
            if not keys %included_subs;

        if (my @missing_subs = grep { !-f path($self->_include_sub_root, $_) } @include_subs)
        {
            $self->log_fatal(
                @missing_subs > 1
                    ? [ 'no definitions available for subs %s!', join(', ', map { "'" . $_  ."'" } @missing_subs) ]
                    : [ 'no definition available for sub \'%s\'!', $missing_subs[0] ]
            );
        }

        my @sub_definitions = map { path($self->_include_sub_root, $_)->slurp_utf8 } @include_subs;
        $content .= "\n"
            . $self->fill_in_string(
                join("\n", @sub_definitions),
                {
                    dist => \($self->zilla),
                    plugin => \$self,
                },
            );
        @included_subs{@include_subs} = (() x @include_subs);
    }

    $file->content($content);
    return;
}

my %sub_prereqs = (
    can_xs => {
        'ExtUtils::CBuilder' => '0.27',
        'File::Temp' => '0',
    },
    can_cc => {
        'Config' => '0',
    },
    can_run => {
        'File::Spec' => '0',
        'Config' => '0',
    },
    parse_args => {
        'Text::ParseWords' => '0',
    },
);

sub register_prereqs
{
    my $self = shift;
    foreach my $required_sub ($self->_all_required_subs)
    {
        my $prereqs = $sub_prereqs{$required_sub};
        $self->zilla->register_prereqs(
            {
                phase => 'configure',
                type  => 'requires',
            },
            %$prereqs,
        ) if $prereqs and %$prereqs;
    }
}

has _include_sub_root => (
    is => 'ro', isa => 'Str',
    lazy => 1,
    default => sub {
        my $self = shift;
        path(File::ShareDir::module_dir($self->meta->name), 'include_subs')->stringify;
    },
);

# indicates subs that require other subs to be included
my %sub_dependencies = (
    can_xs => [ qw(can_cc) ],
    can_cc => [ qw(can_run) ],
    can_run => [ qw(maybe_command) ],
);

has _all_required_subs => (
    isa => 'ArrayRef[Str]',
    traits => ['Array'],
    handles => { _all_required_subs => 'elements' },
    lazy => 1,
    default => sub {
        my $self = shift;
        [ sort $self->_all_required_subs_for($self->include_subs) ];
    },
);

my %required_subs;
sub _all_required_subs_for
{
    my ($self, @subs) = @_;

    @required_subs{@subs} = (() x @subs);

    foreach my $sub (@subs)
    {
        my @subs = @{ $sub_dependencies{$sub} || [] };
        $self->_all_required_subs_for(@subs)
            if notall { exists $required_subs{$_} } @subs;
    }

    return keys %required_subs;
}

__PACKAGE__->meta->make_immutable;
__END__

=pod

=head1 SYNOPSIS

In your F<dist.ini>:

    [DynamicPrereqs]
    -raw = $WriteMakefileArgs{PREREQ_PM}{'Role::Tiny'} = $FallbackPrereqs{'Role::Tiny'} = '1.003000'
    -raw = if can_use('Role::Tiny') and !parse_args()->{PUREPERL_ONLY} and can_xs();
    -include_sub = can_use
    -include_sub = parse_args
    -include_sub = can_xs

or:

    [DynamicPrereqs]
    -delimiter = |
    -raw = |$WriteMakefileArgs{TEST_REQUIRES}{'Devel::Cover'} = $FallbackPrereqs{'Devel::Cover'} = '0'
    -raw = |    if $ENV{EXTENDED_TESTING} or is_smoker();
    -include_sub = is_smoker

or:

    [DynamicPrereqs]
    -raw_from_file = Makefile.args      # code snippet in this file

=head1 DESCRIPTION

This is a L<Dist::Zilla> plugin that inserts code into your F<Makefile.PL> to
indicate dynamic (installer-side) prerequisites.

Code is inserted immediately after the declarations for C<%WriteMakefileArgs>
and C<%FallbackPrereqs>, before they are conditionally modified (when an older
L<ExtUtils::MakeMaker> is installed).  This gives you an opportunity to add to
the C<WriteMakefile> arguments: C<PREREQ_PM>, C<BUILD_REQUIRES>, and
C<TEST_REQUIRES>, and therefore modify the prerequisites in the user's
F<MYMETA.yml> and F<MYMETA.json> based on conditions found on the user's system.

The C<dynamic_config> field in L<metadata|CPAN::Meta::Spec/dynamic_config> is
already set for you.

=for stopwords usecase

You could potentially use this plugin for performing other modifications in
F<Makefile.PL> other than user-side prerequisite modifications, but I can't
think of a situation where this makes sense. Contact me if you have any ideas!

Only F<Makefile.PL> modification is supported at this time. This author
considers the use of L<Module::Build> to be questionable in all circumstances,
and L<Module::Build::Tiny> does not (yet?) support dynamic configuration.

=head1 CONFIGURATION OPTIONS

=head2 C<-raw>

The code to be inserted; must be valid and complete perl statements. You can
reference and modify the already-declared C<%WriteMakefileArgs> and
C<%FallbackPrereqs> variables, as inserted into F<Makefile.PL> by
L<Dist::Zilla::Plugin::MakeMaker> and subclasses (e.g.
L<Dist::Zilla::Plugin::MakeMaker::Awesome> since L<Dist::Zilla> C<5.001>.

This option can be used more than once; lines are added in the order in which they are provided.

This option is pretty low-level; I anticipate its use to be deprecated when
better options are added (see below). In particular, the user should not have
to be aware of existing code in F<Makefile.PL> nor the exact code required to
add prerequisites of various types.

If you use external libraries in the code you are inserting, you B<must> add
these modules to C<configure_requires> prereqs in metadata (e.g. via
C<[Prereqs / ConfigureRequires]> in your F<dist.ini>).

=for Pod::Coverage mvp_multivalue_args mvp_aliases BUILD metadata after_build setup_installer register_prereqs

=head2 C<-delimiter>

(Available since version 0.007)

A string, usually a single character, which is stripped from the beginning of
all C<-raw> lines. This is because the INI file format strips all leading
whitespace from option values, so including this character at the front allows
you to use leading whitespace in an option string, so you can indent blocks of
code properly.

=head2 C<-raw_from_file>

(Available since version 0.010)

A filename that contains the code to be inserted; must be valid and complete
perl statements, as with C<-raw> above.  This file must be part of the build,
but it is pruned from the built distribution.

=head2 C<-include_sub>

(Available since version 0.010)

The name of a subroutine that you intend to call from the code inserted via
C<-raw> or C<-raw_from_file>. Its definition will be included in
F<Makefile.PL>, as well as any helper subs it calls; necessary prerequisite
modules will be added to C<configure requires> metadata.
This option can be used more than once.

Available subs are:

=over 4

=item * C<prompt_default_yes($message)> - takes a string (appending "[Y/n]" to it), returns a boolean; see L<ExtUtils::MakeMaker/prompt>

=item * C<prompt_default_no($message)> - takes a string (appending "[y/N]" to it), returns a boolean; see L<ExtUtils::MakeMaker/prompt>

=item * C<parse_args()> - returns the hashref of options that were passed as arguments to C<perl Makefile.PL>

=item * C<can_xs()> - Secondary compile testing via ExtUtils::CBuilder

=item * C<can_cc()> - can we locate a (the) C compiler

=item * C<can_run()> - check if we can run some command

=item * C<can_use($module, $version (optional))> - checks if a module (optionally, at a specified version) can be loaded

=item * C<is_smoker()> - is the installation on a smoker machine?

=item * C<is_interactive()> - is the installation in an interactive terminal?

=item * C<is_trial()> - is the release a -TRIAL or _XXX-versioned release?

=item * C<is_os($os, ...)> - true if the OS is any of those listed

=item * C<isnt_os($os, ...)> - true if the OS is none of those listed

=item * C<maybe_command> - actually a monkeypatch to C<< MM->maybe_command >> (please keep using the fully-qualified form) to work in Cygwin

=back

=head1 WARNING: UNSTABLE API!

=for stopwords DarkPAN

This plugin is still undergoing active development, and the interfaces B<will>
change and grow as I work through the proper way to do various things.  As I
make changes, I will be using L<http://grep.cpan.me> to find and fix any
upstream users, but I obviously cannot do this for DarkPAN users. Regardless,
please contact me (see below) and I will keep you directly advised of
interface changes.

Future options may include:

=for :list
* C<-condition> a Perl expression that is tested before additional prereqs are added
* C<-phase> the phase in which subsequently-specified module/version pairs will be added
* C<-runtime> a module and version that is added to runtime prereqs should the C<-condition> be satisfied
* C<-test> a module and version that is added to test prereqs should the C<-condition> be satisfied
* C<-build> a module and version that is added to build prereqs should the C<-condition> be satisfied

=head1 SUPPORT

=for stopwords irc

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-DynamicPrereqs>
(or L<bug-Dist-Zilla-Plugin-DynamicPrereqs@rt.cpan.org|mailto:bug-Dist-Zilla-Plugin-DynamicPrereqs@rt.cpan.org>).
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=head1 SEE ALSO

=for :list
* L<Dist::Zilla::Plugin::MakeMaker>
* L<ExtUtils::MakeMaker/Using Attributes and Parameters>
* L<Dist::Zilla::Plugin::OSPrereqs>
* L<Dist::Zilla::Plugin::PerlVersionPrereqs>
* L<Module::Install::Can>

=cut
