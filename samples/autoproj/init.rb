# Define the github handler
require 'autoproj/git_server_configuration'

# Comment this line if you want Autoproj to import the overall shell
# environment. The default is to reset all build-related environment variables,
# forcing the build configuration to set them explicitly, to improve
# repeatability
Autoproj.isolate_environment

# Display CMake/GCC build messages
Autobuild::CMake.show_make_messages = true

# Install each package in a separate directory of install/
#
# This makes the dependencies stricter, so builds that were fine without this
# option might fail with it. However, it is also cleaner (allows to remove
# obsolete package byproducts easily) and allows to turn the
# delete_obsolete_files_in_prefix CMake option, in which autoproj's cmake
# handler will remove installed files that are not part of the package anymore.
Autoproj.config.separate_prefixes = true
Autobuild::CMake.delete_obsolete_files_in_prefix = Autoproj.config.separate_prefixes?

