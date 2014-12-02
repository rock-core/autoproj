require 'find'
require 'fileutils'
require 'autobuild'
require 'set'

def explicit_osdeps_selection(name)
    if !Autoproj.declared_option?("osdeps_#{name}")
	if Autoproj.has_config_key?("osdeps_#{name}")
	    doc_string = "install #{name} from source ?"
	else
	    # Declare the option
	    doc_string =<<-EOT
The #{name} package is listed as a dependency of #{self.name}. It is listed as an operating
system package for other operating systems than yours, and is also listed as a source package.
Since you requested manual updates, I have to ask you:

Do you want me to build #{name} from source ? If you say 'no', you will have to install it yourself.
	    EOT
	end

	Autoproj.configuration_option(
	    "osdeps_#{name}", "boolean",
	    :default => "yes",
	    :doc => doc_string)
    end
    !Autoproj.user_config("osdeps_#{name}")
end

module Autobuild
    class Package
        # The Autoproj::PackageManifest object that describes this package
        attr_accessor :description
        # The set of tags for this package. This is an union of the tags
        # contained in +description+ and the ones explicitely added with
        # #add_tag
        def tags
            result = (@added_tags || Set.new)
            if description
                result |= description.tags.to_set
            end
            result
        end
        # Tags explicitely added with #add_tag
        attr_reader :added_tags
        # Add a tag to the package. Use this if you don't want the tag to be
        # shared with everyone that uses the package (i.e. cannot go in
        # manifest.xml)
        def add_tag(tag)
            @added_tags ||= Set.new
            @added_tags << tag
        end

        # True if this package is tagged with the given tag string
        def has_tag?(tag)
            tags.include?(tag.to_s)
        end

        # Asks autoproj to remove references to the given obsolete oroGen
        # package
        def remove_obsolete_installed_orogen_package(name)
            post_install do
                path = File.join(prefix, 'lib', 'pkgconfig')
                Dir.glob(File.join(path, "#{name}-*.pc")) do |pcfile|
                    Autoproj.message "  removing obsolete file #{pcfile}", :bold
                    FileUtils.rm_f pcfile
                end
                pcfile = File.join(path, "orogen-project-#{name}.pc")
                if File.exists?(pcfile)
                    Autoproj.message "  removing obsolete file #{pcfile}", :bold
                    FileUtils.rm_f pcfile
                end
            end
        end

        # Asks autoproj to remove the given file in the package's installation
        # prefix
        def remove_obsolete_installed_file(*path)
            post_install do
                path = File.join(prefix, *path)
                if File.exists?(path)
                    Autoproj.message "  removing obsolete file #{path}", :bold
                    FileUtils.rm_f path
                end
            end
        end

        # Ask autoproj to run the given block after this package has been
        # imported
        def post_import(&block)
            Autoproj.post_import(self, &block)
        end

        def autoproj_name # :nodoc:
            srcdir.gsub /^#{Regexp.quote(Autoproj.root_dir)}\//, ''
        end

        alias __depends_on__ depends_on
        def depends_on(name)
            if name.respond_to?(:name) # probably a Package object
                name = name.name
            end

            if Autoproj::CmdLine.ignore_dependencies?
                return
            end

            @os_packages ||= Set.new
            pkg_autobuild, pkg_os = partition_package(name)
            pkg_autobuild.each do |pkg|
                __depends_on__(pkg)
            end
            @os_packages |= pkg_os.to_set
        rescue Autoproj::OSDependencies::MissingOSDep
            Autoproj.manifest.add_exclusion(self.name, "it depends on #{name}, which is neither the name of a source package, nor an osdep that is available on this operating system")
        end

        def depends_on_os_package(name)
            depends_on(name)
        end

        def optional_dependency(name)
            if Autoproj::CmdLine.ignore_dependencies?
                return
            end

            optional_dependencies << name
        end

        def partition_package(pkg_name)
            pkg_autobuild, pkg_osdeps = [], []
            Autoproj.manifest.resolve_package_name(pkg_name).each do |type, dep_name|
                if type == :osdeps
                    pkg_osdeps << dep_name
                elsif type == :package
                    pkg_autobuild << dep_name
                else raise Autoproj::InternalError, "expected package type to be either :osdeps or :package, got #{type.inspect}"
                end
            end
            return pkg_autobuild, pkg_osdeps
        end

        def partition_optional_dependencies
            packages, osdeps, disabled = [], [], []
            optional_dependencies.each do |name|
                if !Autoproj.manifest.package_enabled?(name, false)
                    disabled << name
                    next
                end

                pkg_autobuild, pkg_osdeps = partition_package(name)
                valid = pkg_autobuild.all? { |pkg| Autoproj.manifest.package_enabled?(pkg) } &&
                    pkg_osdeps.all? { |pkg| Autoproj.manifest.package_enabled?(pkg) }

                if valid
                    packages.concat(pkg_autobuild)
                    osdeps.concat(pkg_osdeps)
                else
                    disabled << name
                end
            end
            return packages, osdeps, disabled
        end

        def resolve_optional_dependencies
            if !Autoproj::CmdLine.ignore_dependencies?
                packages, osdeps, disabled = partition_optional_dependencies
                packages.each { |pkg| depends_on(pkg) }
                @os_packages ||= Set.new
                @os_packages |= osdeps.to_set
            end
        end

        def optional_dependencies
            @optional_dependencies ||= Set.new
        end

        def os_packages
            @os_packages ||= Set.new
        end
    end

    class Git
        # Reconfigures this importer to use an already existing checkout located
        # in the given autoproj root
        #
        # @param [Autobuild::Package] the package we are dealing with
        # @param [Autoproj::InstallationManifest] the other root's installation
        #   manifest
        def pick_from_autoproj_root(package, installation_manifest)
            other_pkg = installation_manifest[package.name]
            return if !other_pkg || !File.directory?(other_pkg.srcdir)
            self.relocate(other_pkg.srcdir)
            true
        end
    end

    class ArchiveImporter
        # Reconfigures this importer to use an already existing checkout located
        # in the given autoproj root
        #
        # @param [Autobuild::Package] the package we are dealing with
        # @param [Autoproj::InstallationManifest] the other root's installation
        #   manifest
        def pick_from_autoproj_root(package, installation_manifest)
            # Get the cachefile w.r.t. the autoproj root
            cachefile = Pathname.new(self.cachefile).
                relative_path_from(Pathname.new(Autoproj.root_dir)).to_s

            # The cachefile in the other autoproj installation
            other_cachefile = File.join(installation_manifest.path, cachefile)
            if File.file?(other_cachefile)
                self.relocate("file://" + other_cachefile)
                true
            end
        end
    end
end

module Autoproj
    # Subclass of Autobuild::Reporter, used to display a message when the build
    # finishes/fails.
    class Reporter < Autobuild::Reporter
        def error(error)
            error_lines = error.to_s.split("\n")
            Autoproj.message("Command failed", :bold, :red, STDERR)
            Autoproj.message("#{error_lines.shift}", :bold, :red, STDERR)
            error_lines.each do |line|
                Autoproj.message line, STDERR
            end
        end
        def success
            Autoproj.message("Command finished successfully at #{Time.now}", :bold, :green)
            if Autobuild.post_success_message
                Autoproj.message Autobuild.post_success_message
            end
        end
    end

    @file_stack       = Array.new

    def self.package_name_from_options(spec)
        if spec.kind_of?(Hash)
            spec.to_a.first.first.to_str
        else
            spec.to_str
        end
    end

    # @deprecated use Ops.loader.in_package_set or add a proper Loader object to your
    #   class
    def self.in_package_set(package_set, path, &block)
        Ops.loader.in_package_set(package_set, path, &block)
    end

    # @deprecated use Ops.loader.current_file or add a proper Loader object to your
    #   class
    def self.current_file
        Ops.loader.current_file
    end

    # @deprecated use Ops.loader.current_package_set or add a proper Loader object to your
    #   class
    def self.current_package_set
        Ops.loader.current_package_set
    end

    def self.define(package_type, spec, &block)
        package = Autobuild.send(package_type, spec)
        Autoproj.manifest.register_package(package, block, *current_file)
        package
    end

    @loaded_autobuild_files = Set.new

    class << self
        attr_reader :loaded_autobuild_files
    end

    def self.import_autobuild_file(package_set, path)
        return if @loaded_autobuild_files.include?(path)
        Autoproj.load(package_set, path)
        @loaded_autobuild_files << path
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
        end
    end
end

def ignore(*paths)
    paths.each do |p|
        Autobuild.ignore(p)
    end
end

# Adds a new setup block to an existing package
def setup_package(package_name, &block)
    if !block
        raise ConfigError.new, "you must give a block to #setup_package"
    end

    package_definition = Autoproj.manifest.package(package_name)
    if !package_definition
        raise ConfigError.new, "#{package_name} is not a known package"
    elsif package_definition.autobuild.kind_of?(Autobuild::DummyPackage)
        # Nothing to do!
    else
        package_definition.add_setup_block(block)
    end
end

# Common setup for packages
def package_common(package_type, spec, &block)
    package_name = Autoproj.package_name_from_options(spec)

    if Autobuild::Package[package_name]
        current_file = Autoproj.current_file[1]
        old_file     = Autoproj.manifest.definition_file(package_name)
        Autoproj.warn "#{package_name} from #{current_file} is overridden by the definition in #{old_file}"

        return Autobuild::Package[package_name]
    end

    pkg = Autoproj.define(package_type, spec, &block)
    pkg.srcdir = pkg.name
    pkg
end

def import_package(options, &block)
    package_common(:import, options, &block)
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
                pkg.test_utility.source_dir = test_dir
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
def cmake_package(options, &block)
    package_common(:cmake, options) do |pkg|
        pkg.depends_on 'cmake'
        common_make_based_package_setup(pkg)
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
def autotools_package(options, &block)
    package_common(:autotools, options) do |pkg|
        pkg.depends_on 'autotools'
        common_make_based_package_setup(pkg)
        yield(pkg) if block_given?
    end
end

def env_set(name, value)
    Autoproj.env_set(name, value)
end
def env_add(name, value)
    Autoproj.env_add(name, value)
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
def ruby_package(options)
    package_common(:ruby, options) do |pkg|
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
                    pkg.test_utility.source_dir = test_dir
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
def orogen_package(options, &block)
    package_common(:orogen, options) do |pkg|
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

    os_names, os_versions = Autoproj::OSDependencies.operating_system
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

    os_names, os_versions = Autoproj::OSDependencies.operating_system
    matching_archs = architectures.find_all { |arch| os_names.include?(arch[0].downcase) }
    if matching_archs.empty?
        return yield
    elsif matching_archs.all? { |arch| arch[1] && !os_versions.include?(arch[1].downcase) }
        return yield
    end

    # Simply get the current list of packages, yield the block, and exclude all
    # packages that have been added
    current_packages = Autobuild::Package.each(true).map(&:last).map(&:name).to_set
    yield
    new_packages = Autobuild::Package.each(true).map(&:last).map(&:name).to_set -
        current_packages

    new_packages.each do |pkg_name|
        Autoproj.manifest.add_exclusion(pkg_name, "#{pkg_name} is disabled on this operating system")
    end
end

# Defines an import-only package, i.e. a package that is simply checked out but
# not built in any way
def source_package(options)
    package_common(options) do |pkg|
        pkg.srcdir   = pkg.name
        yield(pkg) if block_given?
    end
end

# Define a configuration option
#
# See Autoproj.configuration_option
def configuration_option(*opts, &block)
    Autoproj.configuration_option(*opts, &block)
end

# Retrieves the configuration value for the given option
#
# See Autoproj.user_config
def user_config(key)
    Autoproj.user_config(key)
end

class Autobuild::Git
    # get version information from the importer
    def snapshot(package, target_dir = nil)
        info = Hash.new
        if local_branch != remote_branch
            info['local_branch'] = local_branch
            info['remote_branch'] = remote_branch
        else
            info['branch'] = branch
        end

        begin
            tag = run_git_bare(package, 'describe', '--tags', '--exact-match', 'HEAD').first.strip
            info.merge('tag' => tag, 'commit' => nil)
        rescue Autobuild::SubcommandFailed
            head_commit = rev_parse(package, 'HEAD')
            info.merge('tag' => nil, 'commit' => head_commit)
        end
    end
end

class Autobuild::ArchiveImporter
    def snapshot(package, target_dir = nil)
        if target_dir
            archive_dir = File.join(target_dir, 'archives')
            FileUtils.mkdir_p archive_dir
            FileUtils.cp @cachefile, archive_dir

            { 'url' =>  "file://$AUTOPROJ_SOURCE_DIR/archives/#{File.basename(@cachefile)}" }
        else
            { 'url' => @url.to_s }
        end
    end
end

def package(name)
    Autobuild::Package[name]
end

# Returns true if +name+ is a valid package and is neither excluded nor ignored
# from the build
def package_selected?(name)
    Autoproj.manifest.package_selected?(name, false)
end

# Returns true if +name+ is a valid package and is included in the build
def package_enabled?(name)
    Autoproj.manifest.package_enabled?(name, false)
end

# If used in init.rb, allows to disable automatic imports from specific package
# sets
def disable_imports_from(name)
    Autoproj.manifest.disable_imports_from(name)
end

# Moves the given package to a new subdirectory
def move_package(name, new_dir)
    Autoproj.manifest.move_package(name, new_dir)
end

# Removes all the packages currently added from the given metapackage
#
# Calling this function will make sure that the given metapackage is now empty.
def clear_metapackage(name)
    meta = Autoproj.manifest.metapackage(name)
    meta.packages.clear
end

# Declares a new metapackage, or adds packages to an existing one
def metapackage(name, *packages)
    Autoproj.manifest.metapackage(name, *packages)
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
    Autoproj.manifest.metapackage(pkg_set.name).packages.delete_if do |pkg|
        names.include?(pkg.name)
    end
end

