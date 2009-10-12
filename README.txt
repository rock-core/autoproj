What is Rubotics
----------------
Rubotics is both a tool and a project. The project aims at promoting the use of
Ruby for robotics system, in both the toolchain (development of robotics-related
software) but also on the robots themselves (sensor processing, control, you
name it).

To allow an easy installation and testing of the software that Rubotics
describes, a _tool_ has been developped, that allows an easy integration of the
local operating system (Debian, Ubuntu, Fedora, maybe MacOSX at some point) with
the tools that come in source code form. What you are reading now is the user's
guide for the tool.

The goal of this tool is to ease the pain of installing robotics-related
software. Unlike [the ROS build system](http://ros.org), it is not bound to one build
system, one VCS and one integration framework. The philosophy behind rubotics
is:
 * supports both CMake and autotools, and can be adapted to other tools
 * supports different VCS: cvs, svn, git, plain tarballs.
 * software packages are plain packages, meaning that they can be built and
   installed /outside/ a rubotics tree, and are not tied *at all* to the
   rubotics build system.
 * leverage the actual OS package management system. Right now, only Debian-like
   systems (like Ubuntu) are supported, simply because it is the only one I have
   access to.
 * handle code generation properly

It tries as much as possible to follow the lead of Willow Garage on the package
specification. More specifically, the package manifest files are common between
ROS package management and rubotics (more details in the following of this
document).

Components of a Rubotics installation
-------------------------------------
A rubotics installation is seeded by _sources_. A source is a local or remote
directory in which there is:
 * autobuild scripts that describe what can be built and how it should be built.
   These scripts an also list a set of configuration options that allow to
   parametrize the build. In general, there should be only a limited number of
   such options.
 * a source.yml file which describes the source itself, and where the software
   packages are located (what version control system and what URL).
 * optionally, a file that describe prepackaged dependencies that can be
   installed by using the operating system package management system.

Bootstrapping
-------------
"Bootstrapping" means getting rubotics itself before it can work its magic ...
The canonical way is the following:

 * install Ruby by yourself. On Debian or Ubuntu, this is done with
   done with

   sudo apt-get install wget ruby
   {.cmdline}

 * then, [download this script](rubotics_bootstrap) *in the directory where
   you want to create a rubotics installation*, and run it. This can be done with

   wget http://doudou.github.com/rubotics/rubotics\_bootstrap <br />
   ruby rubotics\_bootstrap
   {.cmdline}

 * follow the instructions printed by the script above :)

Software packages in Rubotics
-----------------------------
In the realm of rubotics, a software package should be a self-contained build
system, that could be built outside of a rubotics tree. In practice, it means
that the package writer should leverage its build system (for instance, cmake)
to discover if the package dependencies are installed, and what are the
appropriate build options that should be given (for instance, include
directories or library names).

As a guideline, we recommend that inter-package dependencies are managed by
using pkg-config.

To describe the package, and more importantly to setup cross-package
dependencies, an optional manifest file can be added. This manifest file is
named manifest.xml. Its format is described later in this user's guide.

