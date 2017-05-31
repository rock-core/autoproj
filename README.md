[![Build Status](https://travis-ci.org/rock-core/autoproj.svg?branch=autoproj-2.0)](https://travis-ci.org/rock-core/autoproj)
[![Gem Version](https://badge.fury.io/rb/autoproj.svg)](http://badge.fury.io/rb/autoproj)
[![Documentation](http://b.repl.ca/v1/yard-docs-blue.png)](http://rubydoc.info/gems/autoproj/frames)

# What is Autoproj

Autoproj allows to easily install and maintain software that is under source
code form (usually from a version control system). It has been designed to support a
package-oriented development process, where each package can have its own
version control repository (think "distributed version control"). It also
provides an easy integration of the local operating system (Debian, Ubuntu,
Fedora, MacOSX).

This tool has been developed over the years. It is now maintained in the frame of the Rock
robotics project (http://rock-robotics.org), to install robotics-related
software -- that is often bleeding edge.

One main design direction for autoproj is that packages can be built with
autoproj without having been designed to be built with autoproj.

The philosophy behind autoproj is:
* supports any type of build system (CMake, autotools, ruby packages, ...)
* supports different VCS: git, plain archives, cvs, svn, ...
* software packages are plain packages, meaning that they can be built and
  installed /outside/ an autoproj tree, and are not tied *at all* to the
  autoproj build system.
* leverage the actual OS package management system. Right now, only Debian-like
  systems (like Ubuntu) are supported, simply because it is the only one I have
  access to.
* handle code generation properly

## Overview of an autoproj installation

The idea in an autoproj installation is that people share _definitions_ for a
set of packages that can depend on each other. Then, anyone can cherry-pick in
these definitions to build its own installation (in practice, one builds a
complete configuration per-project).

Each package definition includes:

* how to get the package's source code
* how to build the package
* on what the package depends. This can be either another package built by
  autoproj, or an operating system package.

See this
page[http://www.rock-robotics.org/stable/documentation/autoproj/writing_manifest.html] for more information.

## Software packages in Autoproj

In the realm of autoproj, a software package should be a self-contained build
system, that could be built outside of an autoproj tree. In practice, it means
that the package writer should leverage its build system (for instance, cmake)
to discover if the package dependencies are installed, and what are the
appropriate build options that should be given (for instance, include
directories or library names).

As a guideline, we recommend that inter-package dependencies are managed by
using pkg-config for C/C++ packages.

To describe the package, and more importantly to setup cross-package
dependencies, an optional manifest file can be
added[http://www.rock-robotics.org/stable/documentation/autoproj/advanced/manifest-xml.html].

# Migrating from v1 to v2

Autoproj 2.0 has been released on the 22nd December 2016 and brought
significant changes both to its internals and to its workflow. What follows
describes the changes brought by v2, from the point of view of someone that
already knows autoproj v1

### Upgrade process

Autoproj 2.x is backward incompatible in two ways: first, it requires
ruby 2.0+. Second, both the workspace layout and the way RubyGems are
handled changed and therefore the upgrade process is pretty complex.

For these reasons, the latest version of autoproj 1.x (1.13.3) will
not automatically upgrade to 2.x. The update to 2.x will have to be
manual. This is going to be a general policy going forward (2.x will
not upgrade to 3.x and so on). Moreover, it will remain possible to
bootstrap an autoproj 1.x workspace using this bootstrap script:

   https://raw.githubusercontent.com/rock-core/autoproj/v1.13.3/bin/autoproj_bootstrap

To bootstrap a new install using autoproj 2.0, just follow the
standard bootstrap process, which did not change. Note that by using
the bootstrap from the 'master' branch on github you *will* bootstrap
using autoproj 2.0.

To upgrade an existing autoproj 1.x install, run the following script
from the root of the installation:

   https://raw.githubusercontent.com/rock-core/autoproj/master/bin/autoproj_install

After the upgrade, one can "downgrade" by simply replacing the new
autoproj-generated env.sh script by the backup the upgrade process did
(env.sh-autoproj-v1). Open a new console, et voila.

### New 2.x workspace

Under 2.x, all autoproj-generated files related to the workspace are
saved under a new .autoproj directory (as e.g. the config files and
remotes). The upgrade process does not delete these to allow for
"downgrading".

In addition, autoproj now uses [bundler](bundler.io) to manage the gems. This means
that, by default, the gems are shared between all autoproj installs,
bundler making sure that upgrading a gem on one install does not
affect another. This makes bootstrapping a lot faster (since already
present gems will be reused) and in the future will allow 'autoproj
versions' and related commands (tag and commit) to pin the gem
versions. It also resolves the gem dependencies globally, thus
detecting and/or handling problems with gems that have conflicting
dependencies (an issue we currently have / had with webgen)

This also means that using the `gem` command to manage the gems is not allowed
anymore.

To add a gem to the workspace, create or edit `autoproj/Gemfile` and add `gem`
entries following [the bundler documentation](http://bundler.io/gemfile.html).
Once the file is edited, run `autoproj osdeps` and reload the updated `env.sh`. 

To remove gems, remove the corresponding line in `autoproj/Gemfile`, run
`autoproj osdeps` and reload env.sh.

Alternatively to the main `autoproj/Gemfile`, files with the `.gemfile`
extension in `autoproj/overrides.d` are also considered

### Proper help for the command-line interface

'autoproj help' is useful (which was definitely NOT the case on 1.x),
showing details about each subcommand as well as all existing command
line options.

### Parallel import

autoproj update and status can now operate in parallel. The default is
to spawn 10 process, but this can be controlled through the
'parallel_import_level' option in .autoproj/config.yml.

Note that for this feature to work well, one has to specify if a
repository needs user interaction (e.g. github private repositories
requiring a password) or not. The generic interactive: option can be
given for any importer, and the private: option can be used for this
purpose in the github handler. The latter also allows to use a
different pull method than for public repositories (and defaults to
the push handler, e.g. http,ssh leads to private repositories using
ssh to pull by default)

### Improved workflow for overrides

To increase convenience, the git importer sets up a remote for each
package set, with the version control information that this package
set expects. So, if you have a rock.core package that is overriden by
myproject, the rock.core remote will point to the URL defined in
rock.core and the myproject remote will point to the overriden URL.
The 'autobuild' remote always points to the final one.

The status and show subcommands learned the --mainline option. With
--mainline, the status is displayed against the VCS without any
overrides applied. With --mainline=rock.core, only the overrides up to
and including rock.core will be applied:

autoproj status --mainline # compare the local state against the
"upstream" state
autoproj status --mainline=my.set # compare the local state against
someone that would have overrides only until 'my.set'

The option is also available to "autoproj show"

### Environment handling

The environment is not global anymore, but per-package. This means
that builds that were missing dependencies could be previously passing
and will fail. It also means that the environment of packages that
have been used but are not anymore will not pollute env.sh.

### Separate build directories

Autoproj.builddir can be set to a full path, in which case every
package's build directory will be placed into a subdirectory of this
path (instead of within the package checkout). This is great to avoid
backing up build files (separating the build/install and source
folders), or to share source files for different build setups.
autoproj locate and acd learned -b or --build to resp. locate or cd
into a package's build directory. This should also improve the usage
of Eclipse in an autoproj environment.

### Improved workflow with heavy branching

Principally when using pull requests, we have a tendency to push a lot
of code on branches. 'autoproj status' becomes a lot more difficult to
interpret as we always have to ask ourselves "is this code on a PR
already ?"

2.0 improves this workflow in two ways:
- "autoproj versions" now looks by default remotely to determine the
"best" remote branch. It can be turned off with the --local option
- autoproj status also checks by default if there is a remote branch,
and displays that information. Additionally, the --snapshot option
tells status to display the status against this "best" branch.

### Plugin support

The autoproj CLI can now be extended with plugins. Two such plugins
are already available:
   autoproj-stats: compute statistics about authorship and
copyright/license information
   autoproj-git: git-aware subcommand (for now, only knows "clean")

A plugin is a gem, but must be installed using the `autoproj plugin` subcommand
to make it available. For instance, `autoproj plugin install autoproj-stats`
will add the 'stats' subcommand to the autoproj command, whose documentation
is available with autoproj help stats

### Other changes

update and build have a working --no-deps option (this was broken pre-2.0)

All subcommands for which it makes sense now accept a package
selection on the command line.

bootstrap learned --seed-config=PATH to provide a base configuration
for the build, useful for automated build environments.

Autoproj pre-2.0 had widely inconsistent behaviour between source and
osdep packages. Hopefully all of them have been fixed. For all intent
and purposes, osdeps and source packages look the same. For instance,
osdep can be excluded or ignored now.

autoproj update learned --force-reset to reset to the expected commit,
bypassing any check. Great for CI environments.

# Developing autoproj 2.x

The best way to use autoproj 2.x from git is to checkout autoproj and
autobuild manually, and write a Gemfile.autoproj-2.0 containing

   source "https://rubygems.org"
   gem "autoproj", path: '/home/doudou/dev/gems/autoproj'
   gem "autobuild", path: '/home/doudou/dev/gems/autobuild'
   gem "utilrb", ">= 3.0.0.a"

Then, pass this gemfile to the --gemfile argument to autoproj_install
or autoproj_bootstrap. Note that one can re-run autoproj_install in an
already bootstrapped autoproj workspace, e.g.

   wget https://raw.githubusercontent.com/rock-core/autoproj/master/bin/autoproj_install
   ruby autoproj_install --gemfile=../Gemfile.autoproj-2.0

