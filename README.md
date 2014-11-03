What is Autoproj
----------------
Autoproj allows to easily install and maintain software that is under source
code form (usually from a version control system). It has been designed to support a
package-oriented development process, where each package can have its own
version control repository (think "distributed version control"). It also
provides an easy integration of the local operating system (Debian, Ubuntu,
Fedora, maybe MacOSX at some point).

This tool has been developed over the years. It is now maintained in the frame of the Rock
robotics project (http://rock-robotics.org), to install robotics-related
software -- that is often bleeding edge.

One main design direction for autoproj is that packages can be built with
autoproj without having been designed to be built with autoproj.

The philosophy behind autoproj is:
* supports any type of build system (CMake and autotools are built-in)
* supports different VCS: cvs, svn, git, plain tarballs.
* software packages are plain packages, meaning that they can be built and
  installed /outside/ an autoproj tree, and are not tied *at all* to the
  autoproj build system.
* leverage the actual OS package management system. Right now, only Debian-like
  systems (like Ubuntu) are supported, simply because it is the only one I have
  access to.
* handle code generation properly

Overview of an autoproj installation
-------------------------------------

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
dependencies, an optional manifest file can be
added[http://www.rock-robotics.org/stable/documentation/autoproj/advanced/manifest-xml.html].

