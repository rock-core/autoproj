What is Autoproj
----------------
Autoproj allows to easily install and maintain software that is under source
code form (usually from a version control system). It has been designed to support a
package-oriented development process, where each package can have its own
version control repository (think "distributed version control"). It also
provides an easy integration of the local operating system (Debian, Ubuntu,
Fedora, maybe MacOSX at some point).

This tool has been developped in the frame of the RubyInMotion project
(http://sites.google.com/site/rubyinmotion), to install robotics-related
software -- that is often bleeding edge. Unlike [the ROS build
system](http://ros.org), it is not bound to one build system, one VCS and one
integration framework. The philosophy behind autoproj
is:
 * supports both CMake and autotools, and can be adapted to other tools
 * supports different VCS: cvs, svn, git, plain tarballs.
 * software packages are plain packages, meaning that they can be built and
   installed /outside/ an autoproj tree, and are not tied *at all* to the
   autoproj build system.
 * leverage the actual OS package management system. Right now, only Debian-like
   systems (like Ubuntu) are supported, simply because it is the only one I have
   access to.
 * handle code generation properly

It tries as much as possible to follow the lead of Willow Garage on the package
specification. More specifically, the package manifest files are common between
ROS package management and autoproj (more details in the following of this
document).

Components of an Autoproj installation
-------------------------------------
A autoproj installation is seeded by _package sets_. A package set is a local or remote
directory in which there is:
 * autobuild scripts that describe what can be built and how it should be built.
   These scripts an also list a set of configuration options that allow to
   parametrize the build. In general, there should be only a limited number of
   such options.
 * a source.yml file which describes the package set itself, and where the software
   packages are located (what version control system and what URL).
 * optionally, a file that describe prepackaged dependencies that can be
   installed by using the operating system package management system.

Bootstrapping
-------------
"Bootstrapping" means getting autoproj itself before it can work its magic ...
The canonical way is the following:

 * install Ruby by yourself. On Debian or Ubuntu, this is done with
   done with

   sudo apt-get install wget ruby
   {.cmdline}

 * then, [download this script](autoproj_bootstrap) *in the directory where
   you want to create an autoproj installation*, and run it. This can be done with

   wget http://doudou.github.com/autoproj/autoproj\_bootstrap <br />
   ruby autoproj\_bootstrap
   {.cmdline}

 * follow the instructions printed by the script above :)

Software packages in Autoproj
-----------------------------
In the realm of autoproj, a software package should be a self-contained build
system, that could be built outside of an autoproj tree. In practice, it means
that the package writer should leverage its build system (for instance, cmake)
to discover if the package dependencies are installed, and what are the
appropriate build options that should be given (for instance, include
directories or library names).

As a guideline, we recommend that inter-package dependencies are managed by
using pkg-config.

To describe the package, and more importantly to setup cross-package
dependencies, an optional manifest file can be added. This manifest file is
named manifest.xml. Its format is described later in this user's guide.

