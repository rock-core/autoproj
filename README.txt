
What is Rubotics
----------------
The goal of this project is to ease the pain of installing robotics-related
software. Unlike (the ROS project)[http://ros.org], it is not bound to one build
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

Profiles
--------
A Rubotics profile is a whole system stack, that you will be able to customize
to fit your needs. The following profiles are available:

 * base
 * drivers
 * libs
 * orocos-base
 * orocos-drivers
 * orocos-libs

The workflow to install packages is the following:
 * use <tt>rubotics get <profile></tt> to get the profile files. These files
   define what packages are available in this profile, where to get the code,
   and how to build it, and will also install the OS software packages.
 * edit the profile's manifest to hand-pick packages you want. By default, a
   profile will build all software that you actually need.
 * use <tt>rubotics build <profile></tt> to actuall build the software.

Then, during the development,
 * <tt>rubotics status</tt> shows the status of all source packages, comparing
   them to their source repositories.
 * <tt>rubotics doc</tt> will generate the documentation
 * <tt>rubotics update</tt> will update the source code for all packages and
   rebuild it. The <tt>--only-update</tt> option allows to *not* build 
 * <tt>rubotics rebuild</tt> will rebuild everything from scratch.

The last two commands accept package IDs to update/rebuild only the specified
package and their dependencies.

Finally, one can update the rubotics system itself:
 * rubotics is installed with RubyGems, so one updates it with <tt>gem
   update</tt>
 * profiles can be updated with <tt>rubotics profile-update</tt>

Filesystem structure
--------------------

 - tools/: generic tools and framework libraries
 - robot/: the actual robot code (see below)

Moreover, when considering specific integration frameworks, as for instance the
Orocos/RTT, an toplevel directory is created, which will contain the code
specific to that integration framework. For instance, the rubotics-orocos
profile will create the following directory structure:

 - tools/
 - robot/
 - orocos/tools/
 - orocos/robot/

As long as it is possible, no code in tools/ and robot/ should contain code that
is specific to the integration framework (in our example, no Orocos-specific
code). It is sometime impossible, as a library can have a generic part and a
framework-specific part. Examples of these situations are all ROS-provided
libraries (unfortunately), and the Orocos Kinematics and Dynamics Library (KDL).

Robot code
----------

These are imported into the robot/ subdirectory, and classified into
subcategories.

 - drivers/: contains sensor/hardware driver libraries
 - lowlevel/: contains lowlevel control libraries, including specialized
   controllers
 - navigation/: contains navigation-related code: mapping, SLAM, motion
   planning, path planning, ...
 - supervision/: contains task-planning and supervision related code including
   task planners, plan management, ...

Installation procedure
----------------------

Each software package will be installed in the following way:
 * the package is checked out or updated
 * the package is built in a build/ subdirectory of its source tree
 * the package is installed in the build/ subdirectory from the toplevel of the
   rubotics installation. After installation, the following filesystem structure
   can be found:
   - tools/
   - robot/
   - tools/orocos/
   - robot/orocos/
   - build/tools/
   - build/robot/
   - build/tools/orocos/
   - build/robot/orocos/

