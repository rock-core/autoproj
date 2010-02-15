require 'find'
require 'fileutils'
require 'autobuild'
require 'set'

class Autobuild::Package
    def autoproj_name # :nodoc:
        srcdir.gsub /^#{Regexp.quote(Autoproj.root_dir)}\//, ''
    end
end

module Autoproj
    # Subclass of Autobuild::Reporter, used to display a message when the build
    # finishes/fails.
    class Reporter < Autobuild::Reporter
        def error(error)
            error_lines = error.to_s.split("\n")
            STDERR.puts color("Build failed: #{error_lines.shift}", :bold, :red)
            STDERR.puts error_lines.join("\n")
        end
        def success
            STDERR.puts color("Build finished successfully at #{Time.now}", :bold, :green)
            if Autobuild.post_success_message
                puts Autobuild.post_success_message
            end
        end
    end

    # Displays a warning message
    def self.warn(message)
        STDERR.puts Autoproj.console.color("  WARN: #{message}", :magenta)
    end

    @file_stack       = Array.new

    def self.package_name_from_options(spec)
        if spec.kind_of?(Hash)
            spec.to_a.first.first.to_str
        else
            spec.to_str
        end
    end

    def self.current_file
        @file_stack.last
    end

    def self.define(package_type, spec, &block)
        package = Autobuild.send(package_type, spec, &block)
        Autoproj.manifest.register_package package, *current_file
    end

    @loaded_autobuild_files = Set.new
    def self.filter_load_exception(error, source, path)
        raise error if Autoproj.verbose
        rx_path = Regexp.quote(path)
        error_line = error.backtrace.find { |l| l =~ /#{rx_path}/ }
        line_number = Integer(/#{rx_path}:(\d+)/.match(error_line)[1])
        if source.local?
            raise ConfigError, "#{path}:#{line_number}: #{error.message}", error.backtrace
        else
            raise ConfigError, "#{File.basename(path)}(source=#{source.name}):#{line_number}: #{error.message}", error.backtrace
        end
    end

    def self.import_autobuild_file(source, path)
        return if @loaded_autobuild_files.include?(path)

        @file_stack.push([source, File.basename(path)])
        begin
            Kernel.load path
        rescue Exception => e
            filter_load_exception(e, source, path)
        end
        @loaded_autobuild_files << path

    ensure
        @file_stack.pop
    end
end

# Sets up a documentation target on pkg that runs 'rake <target>'
def ruby_doc(pkg, target = 'doc')
    pkg.doc_task do
        pkg.progress "generating documentation for %s"
        pkg.doc_disabled unless File.file?('Rakefile')
        Autobuild::Subprocess.run pkg.name, 'doc', 'rake', target
    end

end

# Common setup for packages
def package_common(package_type, spec) # :nodoc:
    package_name = Autoproj.package_name_from_options(spec)

    begin
        Rake::Task[package_name]
        Autoproj.warn "#{package_name} from #{Autoproj.current_file[0]} is overriden by the definition in #{Autoproj.definition_source(package_name)}"
        return
    rescue
    end

    # Check if this package is ignored
    if Autoproj.manifest.ignored?(package_name)
        return Autoproj.define(:dummy, spec)
    end

    Autoproj.define(package_type, spec) do |pkg|
        pkg.srcdir   = pkg.name
        yield(pkg) if block_given?
    end
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

# Common setup for Ruby packages
def ruby_common(pkg) # :nodoc:
    def pkg.prepare_for_forced_build
        super
        extdir = File.join(srcdir, 'ext')
        if File.directory?(extdir)
            Find.find(extdir) do |file|
                next if file !~ /\<Makefile\>|\<CMakeCache.txt\>$/
                FileUtils.rm_rf file
            end
        end
    end
    def pkg.prepare_for_rebuild
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

    def pkg.prepare
        super
        Autobuild.update_environment srcdir
    end

    pkg.post_install do
        Autobuild.progress "setting up Ruby package #{pkg.name}"
        Autobuild.update_environment pkg.srcdir
        if File.file?('Rakefile')
            if File.directory?('ext')
                Autobuild::Subprocess.run pkg.name, 'post-install', 'rake', 'setup'
            end
        end
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
    package_common(:import, options) do |pkg|
        class << pkg
            attr_accessor :doc_target
        end

        ruby_common(pkg)
        yield(pkg) if block_given?
        unless pkg.has_doc?
            ruby_doc(pkg, pkg.doc_target || 'redocs')
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

