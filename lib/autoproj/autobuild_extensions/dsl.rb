require 'find'
require 'fileutils'
require 'autobuild'
require 'set'

module Autoproj
    # @deprecated use Workspace.config.ruby_executable instead, or
    #   Autoproj.config.ruby_executable if you don't have a workspace context
    #   object
    def self.ruby_executable
        config.ruby_executable
    end

    module CmdLine
        # @deprecated use Workspace.config.ruby_executable instead, or
        #   Autoproj.config.ruby_executable if you don't have a workspace context
        #   object
        def self.ruby_executable
            Autoproj.config.ruby_executable
        end
    end

    # @api private
    #
    # Helper method that extracts the package name from a Rake-style package
    # definition (e.g. package_name => package_deps)
    def self.package_name_from_options(spec)
        if spec.kind_of?(Hash)
            spec.to_a.first.first.to_str
        else
            spec.to_str
        end
    end

    # @deprecated use Autoproj.workspace.in_package_set or add a proper Loader object to your
    #   class
    def self.in_package_set(package_set, path, &block)
        Autoproj.warn_deprecated __method__, "use Autoproj.workspace.in_package_set instead"
        Autoproj.workspace.in_package_set(package_set, path, &block)
    end
    # @deprecated use Autoproj.workspace.current_file or add a proper Loader object to your
    #   class
    def self.current_file
        Autoproj.warn_deprecated __method__, "use AUtoproj.workspace.current_file instead"
        Autoproj.workspace.current_file
    end
    # @deprecated use Autoproj.workspace.current_package_set or add a proper Loader object to your
    #   class
    def self.current_package_set
        Autoproj.warn_deprecated __method__, "use Autoproj.workspace.current_package_set instead"
        Autoproj.workspace.current_package_set
    end

    # @deprecated use {Workspace#define_package} directly instead.
    #   Beware that the return value changed from Autobuild::Package to
    #   Autoproj::PackageDefinition
    def self.define(package_type, spec, &block)
        Autoproj.warn_deprecated __method__, "use Autoproj.workspace.define_package instead (and beware that the return value changed from Autobuild::Package to Autoproj::PackageDefinition)"
        workspace.define_package(package_type, spec, block, *current_file).
            autobuild
    end

    def self.loaded_autobuild_files
        Autoproj.warn_deprecated __method__, "use Autoproj.workspace.loaded_autobuild_files"
        Autoproj.workspace.loaded_autobuild_files
    end

    def self.import_autobuild_file(package_set, path)
        Autoproj.warn_deprecated __method__, "use Autoproj.workspace.import_autobuild_file"
        Autoproj.workspace.import_autobuild_file(package_set, path)
    end

    def self.find_topmost_directory_containing(dir, glob_pattern = nil)
        result = nil
        while dir != "/"
            match = false
            if glob_pattern
                if !Dir.glob(File.join(dir, glob_pattern)).empty?
                    match = true
                end
            end

            if !match && block_given? && yield(dir)
                match = true
            end
            if !match && result
                return result
            elsif match
                result = dir
            end

            dir = File.dirname(dir)
        end
    end

    # Tries to find a handler automatically for 'full_path'
    def self.package_handler_for(full_path)
        if !Dir.enum_for(:glob, File.join(full_path, "*.orogen")).to_a.empty?
            return "orogen_package", full_path
        elsif File.file?(File.join(full_path, "CMakeLists.txt"))
            toplevel_dir = find_topmost_directory_containing(full_path) do |dir|
                cmakelists = File.join(dir, 'CMakeLists.txt')
                File.file?(cmakelists) &&
                    (File.read(cmakelists) =~ /PROJECT/i)
            end
            toplevel_dir ||= find_topmost_directory_containing(full_path, 'CMakeLists.txt')

            return "cmake_package", toplevel_dir
        elsif dir = find_topmost_directory_containing(full_path, "Rakefile") ||
            find_topmost_directory_containing(full_path, "lib/*.rb")

            return "ruby_package", dir
        elsif (dir = find_topmost_directory_containing(full_path, 'setup.py')) ||
             (dir = find_topmost_directory_containing(full_path, File.join(File.basename(full_path), "*.py")))
            return 'python_package', dir
        end
    end
end

def ignore(*paths)
    paths.each do |p|
        Autobuild.ignore(p)
    end
end

# Adds a new setup block to an existing package
def setup_package(package_name, workspace: Autoproj.workspace, &block)
    if !block
        raise ConfigError.new, "you must give a block to #setup_package"
    end

    package_definition = workspace.manifest.find_package_definition(package_name)
    if !package_definition
        raise ConfigError.new, "#{package_name} is not a known package"
    elsif package_definition.autobuild.kind_of?(Autobuild::DummyPackage)
        # Nothing to do!
    else
        package_definition.add_setup_block(block)
    end
end

# Common setup for packages
def package_common(package_type, spec, workspace: Autoproj.workspace, &block)
    package_name = Autoproj.package_name_from_options(spec)

    if existing_package = workspace.manifest.find_package_definition(package_name)
        current_file = workspace.current_file[1]
        old_file     = existing_package.file
        Autoproj.warn "#{package_name} from #{current_file} is overridden by the definition in #{old_file}"
        return existing_package.autobuild
    end

    pkg = workspace.define_package(package_type, spec, block, *workspace.current_file)
    pkg.autobuild.srcdir = pkg.name
    pkg
end

def import_package(name, workspace: Autoproj.workspace, &block)
    package_common(:import, name, workspace: Autoproj.workspace, &block)
end

def python_package(name, workspace: Autoproj.workspace, &block)
    package_common(:python, name, workspace: Autoproj.workspace, &block)
end

def common_make_based_package_setup(pkg)
    unless pkg.has_doc? && pkg.doc_dir
        pkg.with_doc do
            doc_html = File.join(pkg.builddir, 'doc', 'html')
            if File.directory?(doc_html)
                pkg.doc_dir = doc_html
            end
        end
    end
    if !pkg.test_utility.has_task?
        if !pkg.test_utility.source_dir
            test_dir = File.join(pkg.srcdir, 'test')
            if File.directory?(test_dir)
                pkg.test_utility.source_dir = File.join(pkg.builddir, 'test', 'results')
            end
        end

        if pkg.test_utility.source_dir
            pkg.with_tests
        end
    end
end

# Define a cmake package
#
# Example:
#
#   cmake_package 'package_name' do |pkg|
#       pkg.define "CMAKE_BUILD_TYPE", "Release"
#   end
#
# +pkg+ is an Autobuild::CMake instance. See the Autobuild API for more
# information.
def cmake_package(name, workspace: Autoproj.workspace)
    package_common(:cmake, name, workspace: workspace) do |pkg|
        pkg.depends_on 'cmake'
        common_make_based_package_setup(pkg)
        yield(pkg) if block_given?
    end
end

# Define a package that was originall designed for Catkin
def catkin_package(name, workspace: Autoproj.workspace)
    cmake_package(name, workspace: workspace) do |pkg|
        pkg.use_package_xml = true
        yield(pkg) if block_given?
    end
end

# Define an autotools package
#
# Example:
#   autotools_package 'package_name' do |pkg|
#       pkg.configureflags << "--enable-llvm"
#   end
#
# +pkg+ is an Autobuild::Autotools instance. See the Autobuild API for more
# information.
def autotools_package(name, workspace: Autoproj.workspace)
    package_common(:autotools, name, workspace: workspace) do |pkg|
        pkg.depends_on 'autotools'
        common_make_based_package_setup(pkg)
        yield(pkg) if block_given?
    end
end

# @deprecated use Autoproj.env.set instead
def env_set(name, value)
    Autoproj.warn_deprecated __method__, "use Autoproj.env.set instead"
    Autoproj.env.set(name, value)
end

# @deprecated use Autoproj.env.add instead
def env_add(name, value)
    Autoproj.warn_deprecated __method__, "use Autoproj.env.add instead"
    Autoproj.env.add(name, value)
end


# Defines a Ruby package
#
# Example:
#
#   ruby_package 'package_name' do |pkg|
#       pkg.doc_target = 'doc'
#   end
#
# +pkg+ is an Autobuild::Importer instance. See the Autobuild API for more
# information.
def ruby_package(name, workspace: Autoproj.workspace)
    package_common(:ruby, name, workspace: workspace) do |pkg|
        pkg.prefix = pkg.srcdir

        # Documentation code. Ignore if the user provided its own documentation
        # task, or disabled the documentation generation altogether by setting
        # rake_doc_task to nil
        if !pkg.has_doc? && pkg.rake_doc_task
            pkg.with_doc
        end
        if !pkg.test_utility.has_task?
            if !pkg.test_utility.source_dir
                test_dir = File.join(pkg.srcdir, 'test')
                if File.directory?(test_dir)
                    pkg.test_utility.source_dir = File.join(pkg.srcdir, '.test-results')
                    FileUtils.mkdir_p pkg.test_utility.source_dir
                end
            end

            if pkg.test_utility.source_dir
                pkg.with_tests
            end
        end

        yield(pkg) if block_given?
    end
end

# Defines an oroGen package. By default, autoproj will look for an orogen file
# called package_basename.orogen if the package is called dir/package_basename
#
# Example:
#   orogen_package 'package_name' do |pkg|
#       pkg.orogen_file = "my.orogen"
#       pkg.corba = false
#   end
#
# +pkg+ is an Autobuild::Orogen instance. See the Autobuild API for more
# information.
def orogen_package(name, workspace: Autoproj.workspace)
    package_common(:orogen, name, workspace: workspace) do |pkg|
        common_make_based_package_setup(pkg)
        yield(pkg) if block_given?
    end
end

# Declare that the packages declared in the block should be built only on the
# given operating system. OS descriptions are space-separated strings containing
# OS name and version.
#
# The block will simply be ignored if run on another architecture
def only_on(*architectures)
    architectures = architectures.map do |name|
        if name.respond_to?(:to_str)
            [name]
        else name
        end
    end

    os_names, os_versions = Autoproj.workspace.operating_system
    matching_archs = architectures.find_all { |arch| os_names.include?(arch[0].downcase) }
    if matching_archs.empty?
        return
    elsif matching_archs.none? { |arch| !arch[1] || os_versions.include?(arch[1].downcase) }
        return
    end

    yield
end

# Declare that the packages declared in the block should not be built in the
# given operating system. OS descriptions are space-separated strings containing
# OS name and version.
#
# An error will occur if the user tries to build it on one of those
# architectures
def not_on(*architectures)
    architectures = architectures.map do |name|
        if name.respond_to?(:to_str)
            [name]
        else name
        end
    end

    os_names, os_versions = Autoproj.workspace.operating_system
    matching_archs = architectures.find_all { |arch| os_names.include?(arch[0].downcase) }
    if matching_archs.empty?
        return yield
    elsif matching_archs.all? { |arch| arch[1] && !os_versions.include?(arch[1].downcase) }
        return yield
    end

    # Simply get the current list of packages, yield the block, and exclude all
    # packages that have been added
    manifest = Autoproj.workspace.manifest
    current_packages = manifest.each_autobuild_package.map(&:name).to_set
    yield
    new_packages = manifest.each_autobuild_package.map(&:name).to_set -
        current_packages

    new_packages.each do |pkg_name|
        manifest.exclude_package(pkg_name, "#{pkg_name} is disabled on this operating system")
    end
end

# Defines an import-only package, i.e. a package that is simply checked out but
# not built in any way
def source_package(options, workspace: Autoproj.workspace)
    package_common(options, workspace: workspace) do |pkg|
        pkg.srcdir   = pkg.name
        yield(pkg) if block_given?
    end
end

# @deprecated use Autoproj.config.declare instead
def configuration_option(*opts, &block)
    Autoproj.warn_deprecated __method__, "use Autoproj.config.declare instead"
    Autoproj.config.declare(*opts, &block)
end

# @deprecated use Autoproj.config.get instead
def user_config(key)
    Autoproj.warn_deprecated __method__, "use Autoproj.config.get instead"
    Autoproj.config.get(key)
end

def package(name)
    Autoproj.workspace.manifest.find_autobuild_package(name)
end

# Returns true if +name+ is a valid package and is neither excluded nor ignored
# from the build
def package_selected?(name)
    Autoproj.workspace.manifest.package_selected?(name, false)
end

# Returns true if +name+ is a valid package and is included in the build
def package_enabled?(name)
    Autoproj.workspace.manifest.package_enabled?(name, false)
end

# If used in init.rb, allows to disable automatic imports from specific package
# sets
def disable_imports_from(name)
    raise NotImplementedError, "not implemented in autoproj v2"
end

# Moves the given package to a new subdirectory
def move_package(name, new_dir)
    Autoproj.workspace.manifest.move_package(name, new_dir)
end

# Removes all the packages currently added from the given metapackage
#
# Calling this function will make sure that the given metapackage is now empty.
def clear_metapackage(name)
    meta = Autoproj.workspace.manifest.metapackage(name)
    meta.clear
end

# Declares a new metapackage, or adds packages to an existing one
def metapackage(name, *packages)
    Autoproj.workspace.manifest.metapackage(name, *packages)
end

# This can be used only during the load of a package set
#
# It defines the set of packages that will be built if 'package_set_name' is
# used. By default, all of the package set's packages are included. After a call
# to default_packages, only the packages listed (and their dependencies) are.
def default_packages(*names)
    pkg_set = Autoproj.current_package_set
    clear_metapackage(pkg_set.name)
    metapackage(pkg_set.name, *names)
end

# This can be used only during the load of a package set
#
# It removes the given packages from the set of packages that will be built if
# 'package_set_name' is used. By default, all of the package set's packages are
# included. After a call to default_packages, only the packages listed (and
# their dependencies) are.
def remove_from_default(*names)
    pkg_set = Autoproj.current_package_set
    metapackage = Autoproj.workspace.manifest.metapackage(pkg_set.name)
    names.each do |pkg_name|
        metapackage.remove(pkg_name)
    end
end

def renamed_package(current_name, old_name, options)
    if options[:obsolete] && !Autoproj.workspace.manifest.explicitely_selected_in_layout?(old_name)
        import_package old_name
        Autoproj.workspace.manifest.exclude_package old_name, "#{old_name} has been renamed to #{current_name}, you still have the option of using the old name by adding '- #{old_name}' explicitely in the layout in autoproj/manifest, but be warned that the name will stop being usable at all in the near future"
    else
        metapackage old_name, current_name
    end
end


