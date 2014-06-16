# NAME

Dist::Zilla::Plugin::DynamicPrereqs - Specify dynamic (user-side) prerequisites for your distribution

# VERSION

version 0.005

# SYNOPSIS

In your `dist.ini`:

    [DynamicPrereqs]
    -raw = $WriteMakefileArgs{PREREQ_PM}{'Role::Tiny'} = $FallbackPrereqs{'Role::Tiny'} = '1.003000'
    -raw = if eval { require Role::Tiny; 1 };

or:

    [DynamicPrereqs]
    -raw = $WriteMakefileArgs{TEST_REQUIRES}{'Devel::Cover'} = $FallbackPrereqs{'Devel::Cover'} = '0'
    -raw = if $ENV{EXTENDED_TESTING};

# DESCRIPTION

This is a [Dist::Zilla](https://metacpan.org/pod/Dist::Zilla) plugin that inserts code into your `Makefile.PL` to
indicate dynamic (installer-side) prerequisites.

Code is inserted immediately after the declarations for `%WriteMakefileArgs`
and `%FallbackPrereqs`, before they are conditionally modified (when an older
[ExtUtils::MakeMaker](https://metacpan.org/pod/ExtUtils::MakeMaker) is installed).  This gives you an opportunity to add to
the `WriteMakefile` arguments: `PREREQ_PM`, `BUILD_REQUIRES`, and
`TEST_REQUIRES`, and therefore modify the prerequisites in the user's
`MYMETA.yml` and `MYMETA.json` based on conditions found on the user's system.

The `dynamic_config` field in [metadata](https://metacpan.org/pod/CPAN::Meta::Spec#dynamic_config) is
already set for you.

You could potentially use this plugin for performing other modifications in
`Makefile.PL` other than user-side prerequisite modifications, but I can't
think of a situation where this makes sense. Contact me if you have any ideas!

Only `Makefile.PL` modification is supported at this time. This author
considers the use of [Module::Build](https://metacpan.org/pod/Module::Build) to be questionable in all circumstances,
and [Module::Build::Tiny](https://metacpan.org/pod/Module::Build::Tiny) does not (yet?) support dynamic configuration.

# CONFIGURATION OPTIONS

## `-raw`

The code to be inserted; must be valid and complete perl statements. You can
reference and modify the already-declared `%WriteMakefileArgs` and
`%FallbackPrereqs` variables, as inserted into `Makefile.PL` by
[Dist::Zilla::Plugin::MakeMaker](https://metacpan.org/pod/Dist::Zilla::Plugin::MakeMaker) and subclasses (e.g.
[Dist::Zilla::Plugin::MakeMaker::Awesome](https://metacpan.org/pod/Dist::Zilla::Plugin::MakeMaker::Awesome) since [Dist::Zilla](https://metacpan.org/pod/Dist::Zilla) `5.001`.

This option can be used more than once; lines are added in the order in which they are provided.

This option is pretty low-level; I anticipate its use to be deprecated when
better options are added (see below). In particular, the user should not have
to be aware of existing code in `Makefile.PL` nor the exact code required to
add prerequisites of various types.

If you use external libraries in the code you are inserting, you **must** add
these modules to `configure_requires` prereqs in metadata (e.g. via
`[Prereqs / ConfigureRequires]` in your `dist.ini`).

# WARNING: UNSTABLE API!

This plugin is still undergoing active development, and the interfaces **will**
change and grow as I work through the proper way to do various things.  As I
make changes, I will be using [http://grep.cpan.me](http://grep.cpan.me) to find and fix any
upstream users, but I obviously cannot do this for DarkPAN users. Regardless,
please contact me (see below) and I will keep you directly advised of
interface changes.

Future options may include:

- `-condition` a Perl expression that is tested before additional prereqs are added
- `-phase` the phase in which subsequently-specified module/version pairs will be added
- `-runtime` a module and version that is added to runtime prereqs should the `-condition` be satisfied
- `-test` a module and version that is added to test prereqs should the `-condition` be satisfied
- `-build` a module and version that is added to build prereqs should the `-condition` be satisfied

It is also quite possible that there will be customized condition options,
e.g. `-can_xs`, that will automatically provide common subroutines for use in
condition expressions.

# SUPPORT

Bugs may be submitted through [the RT bug tracker](https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-DynamicPrereqs)
(or [bug-Dist-Zilla-Plugin-DynamicPrereqs@rt.cpan.org](mailto:bug-Dist-Zilla-Plugin-DynamicPrereqs@rt.cpan.org)).
I am also usually active on irc, as 'ether' at `irc.perl.org`.

# SEE ALSO

- [Dist::Zilla::Plugin::MakeMaker](https://metacpan.org/pod/Dist::Zilla::Plugin::MakeMaker)
- ["Using Attributes and Parameters" in ExtUtils::MakeMaker](https://metacpan.org/pod/ExtUtils::MakeMaker#Using-Attributes-and-Parameters)

# AUTHOR

Karen Etheridge <ether@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Karen Etheridge.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
