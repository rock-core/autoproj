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
                    Autoproj.progress "  removing obsolete file #{pcfile}", :bold
                    FileUtils.rm_f pcfile
                end
                pcfile = File.join(path, "orogen-project-#{name}.pc")
                if File.exists?(pcfile)
                    Autoproj.progress "  removing obsolete file #{pcfile}", :bold
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
                    Autoproj.progress "  removing obsolete file #{path}", :bold
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
            if Autoproj::CmdLine.ignore_dependencies?
                return
            end

            @os_packages ||= Set.new
            @ignored_os_dependencies ||= Set.new

            if @os_packages.include?(name) || @ignored_os_dependencies.include?(name)
                return
            end

            explicit_selection  = Autoproj.manifest.explicitly_selected_package?(name)
	    osdeps_availability = Autoproj.osdeps.availability_of(name)
            available_as_source = Autobuild::Package[name]

	    # Prefer OS packages to source packages
            if !explicit_selection 
                if osdeps_availability == Autoproj::OSDependencies::AVAILABLE
                    @os_packages << name
                    return
                end

                if osdeps_availability == Autoproj::OSDependencies::UNKNOWN_OS
                    # If we can't handle that OS, but other OSes have a
                    # definition for it, we assume that it can be installed as
                    # an external package. However, if it is also available as a
                    # source package, prompt the user
                    if !available_as_source || explicit_osdeps_selection(name)
                        @os_packages << name
                        return
                    end
                end


                if !available_as_source
                    begin
                        # Call osdeps to get a proper error message
                        osdeps, gems = Autoproj.osdeps.partition_packages([name].to_set, name => [self.name])
                        Autoproj.osdeps.resolve_os_dependencies(osdeps)
                    rescue ConfigError => e
                        if osdeps_availability != Autoproj::OSDependencies::NO_PACKAGE && !Autoproj.osdeps.installs_os_packages?
                            Autoproj.warn "in #{File.join(srcdir, 'manifest.xml')}: #{e.message}"
                            Autoproj.warn "this osdeps dependency is simply ignored as you asked autoproj to not install osdeps packages"
                            @ignored_os_dependencies << name
                            # We are not asked to install OS packages, just ignore
                            return
                        end
                        raise
                    end
                    # Should never reach further than that
                end
            end


            __depends_on__(name) # to get the error message
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

        def resolve_optional_dependencies
            optional_dependencies.each do |name|
                if Autobuild::Package[name] && Autoproj.manifest.package_enabled?(name)
                    if Autoproj.verbose
                        STDERR.puts "adding optional dependency #{self.name} => #{name}"
                    end
                    depends_on(name)
                elsif Autoproj.verbose
                    STDERR.puts "NOT adding optional dependency #{self.name} => #{name}"
                end
            end
        end

        def optional_dependencies
            @optional_dependencies ||= Set.new
        end

        def os_packages
            @os_packages ||= Set.new
        end
    end
end

module Autoproj
    # Subclass of Autobuild::Reporter, used to display a message when the build
    # finishes/fails.
    class Reporter < Autobuild::Reporter
        def error(error)
            error_lines = error.to_s.split("\n")
            Autoproj.progress("Build failed: #{error_lines.shift}", :bold, :red)
            error_lines.each do |line|
                Autoproj.progress line
            end
        end
        def success
            Autoproj.progress("Build finished successfully at #{Time.now}", :bold, :green)
            if Autobuild.post_success_message
                Autoproj.progress Autobuild.post_success_message
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

    # Returns the information about the file that is currently being loaded
    #
    # The return value is [source, path], where +source+ is the Source instance
    # and +path+ is the path of the file w.r.t. the autoproj root directory
    def self.current_file
        @file_stack.last
    end

    def self.define(package_type, spec, &block)
        package = Autobuild.send(package_type, spec)
        Autoproj.manifest.register_package(package, block, *current_file)
        package
    end

    @loaded_autobuild_files = Set.new
    def self.filter_load_exception(error, source, path)
        raise error if Autoproj.verbose
        rx_path = Regexp.quote(path)
        if error_line = error.backtrace.find { |l| l =~ /#{rx_path}/ }
            if line_number = Integer(/#{rx_path}:(\d+)/.match(error_line)[1])
                line_number = "#{line_number}:"
            end

            if source.local?
                raise ConfigError.new(path), "#{path}:#{line_number} #{error.message}", error.backtrace
            else
                raise ConfigError.new(path), "#{File.basename(path)}(source=#{source.name}):#{line_number} #{error.message}", error.backtrace
            end
        else
            raise error
        end
    end

    def self.in_package_set(source, path)
        @file_stack.push([source, File.expand_path(path).gsub(/^#{Regexp.quote(Autoproj.root_dir)}\//, '')])
        yield
    ensure
        @file_stack.pop
    end

    def self.import_autobuild_file(source, path)
        return if @loaded_autobuild_files.include?(path)

        in_package_set(source, File.expand_path(path).gsub(/^#{Regexp.quote(Autoproj.root_dir)}\//, '')) do
            begin
                Kernel.load path
            rescue ConfigError => e
                raise
            rescue Exception => e
                filter_load_exception(e, source, path)
            end
            @loaded_autobuild_files << path
        end
    end

    # Tries to find a handler automatically for 'full_path'
    def self.package_handler_for(full_path)
        if !Dir.enum_for(:glob, File.join(full_path, "*.orogen")).to_a.empty?
            "orogen_package"
        elsif File.file?(File.join(full_path, "CMakeLists.txt"))
            "cmake_package"
        elsif File.directory?(File.join(full_path, "lib")) &&
            !Dir.enum_for(:glob, File.join(full_path, "*.rb")).to_a.empty?
            "ruby_package"
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
    end
    package_definition.add_setup_block(block)
end

# Common setup for packages
def package_common(package_type, spec, &block) # :nodoc:
    package_name = Autoproj.package_name_from_options(spec)

    if Autobuild::Package[package_name]
        current_file = Autoproj.current_file[1]
        old_file     = Autoproj.manifest.definition_file(package_name)
        Autoproj.warn "#{package_name} from #{current_file} is overriden by the definition in #{old_file}"

        return
    end

    # Check if this package is ignored
    if Autoproj.manifest.ignored?(package_name)
        return Autoproj.define(:dummy, spec)
    end

    pkg = Autoproj.define(package_type, spec, &block)
    pkg.srcdir = pkg.name
    pkg
end

def import_package(options, &block)
    package_common(:import, options, &block)
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
        Autoproj.add_build_system_dependency 'cmake'
        yield(pkg) if block_given?
        unless pkg.has_doc?
            pkg.with_doc do
                doc_html = File.join('doc', 'html')
                if File.directory? doc_html
                    pkg.doc_dir = doc_html
                end
            end
        end
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
        Autoproj.add_build_system_dependency 'autotools'
        yield(pkg) if block_given?
        unless pkg.has_doc?
            pkg.with_doc do
                doc_html = File.join('doc', 'html')
                if File.directory? doc_html
                    pkg.doc_dir = doc_html
                end
            end
        end
    end
end

# This module is used to extend importer packages to handle ruby packages
# properly
module Autoproj::RubyPackage
    def prepare_for_forced_build # :nodoc:
        super
        extdir = File.join(srcdir, 'ext')
        if File.directory?(extdir)
            Find.find(extdir) do |file|
                next if file !~ /\<Makefile\>|\<CMakeCache.txt\>$/
                FileUtils.rm_rf file
            end
        end
    end

    def prepare_for_rebuild # :nodoc:
        super
        extdir = File.join(srcdir, 'ext')
        if File.directory?(extdir)
            Find.find(extdir) do |file|
                if File.directory?(file) && File.basename(file) == "build"
                    FileUtils.rm_rf file
                    Find.prune
                end
            end
            Find.find(extdir) do |file|
                if File.basename(file) == "Makefile"
                    Autobuild::Subprocess.run self, 'build', Autobuild.tool("make"), "-C", File.dirname(file), "clean"
                end
            end
        end
    end

    def import
        super

        Autobuild.update_environment srcdir
        libdir = File.join(srcdir, 'lib')
        if File.directory?(libdir)
            Autobuild.env_add_path 'RUBYLIB', libdir
        end
    end

    # The Rake task that is used to set up the package. Defaults to "default".
    # Set to nil to disable setup altogether
    attr_accessor :rake_setup_task
    # The Rake task that is used to generate documentation. Defaults to "doc".
    # Set to nil to disable documentation generation
    attr_accessor :rake_doc_task
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
    package_common(:import, options) do |pkg|
        pkg.exclude << /\.so$/
        pkg.exclude << /Makefile$/
        pkg.exclude << /mkmf.log$/
        pkg.exclude << /\.o$/

        pkg.extend Autoproj::RubyPackage
        pkg.rake_setup_task = "default"
        pkg.rake_doc_task   = "redocs"

        # Set up code
        pkg.post_install do
            Autobuild.progress "setting up Ruby package #{pkg.name}"
            Autobuild.update_environment pkg.srcdir
            # Add lib/ unconditionally, as we know that it is a ruby package.
            # Autobuild will add it only if there is a .rb file in the directory
            libdir = File.join(pkg.srcdir, 'lib')
            if File.directory?(libdir)
                Autobuild.env_add_path 'RUBYLIB', libdir
            end

            if pkg.rake_setup_task && File.file?(File.join(pkg.srcdir, 'Rakefile'))
                Autobuild::Subprocess.run pkg, 'post-install',
                    'rake', pkg.rake_setup_task
            end
        end

        yield(pkg) if block_given?

        # Documentation code. Ignore if the user provided its own documentation
        # task, or disabled the documentation generation altogether by setting
        # rake_doc_task to nil
        if !pkg.has_doc? && pkg.rake_doc_task
            pkg.doc_task do
                pkg.progress "generating documentation for %s"
                Autobuild::Subprocess.run pkg, 'doc', 'rake', pkg.rake_doc_task
            end
        end
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
    def snapshot(package, target_dir)
        Dir.chdir(package.srcdir) do
            head_commit   = `git rev-parse #{branch}`.chomp
            { 'commit' => head_commit }
        end
    end
end

class Autobuild::ArchiveImporter
    def snapshot(package, target_dir)
        archive_dir = File.join(target_dir, 'archives')
        FileUtils.mkdir_p archive_dir
        FileUtils.cp @cachefile, archive_dir

        { 'url' =>  File.join('$AUTOPROJ_SOURCE_DIR', File.basename(@cachefile)) }
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
