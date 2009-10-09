require 'autobuild'
require 'set'

module Rubotics
    class RuboticsReporter < Autobuild::Reporter
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

    def self.warn(message)
        STDERR.puts "WARN: #{message}"
    end

    @definition_files = Hash.new
    @file_stack       = Array.new
    class << self
        attr_reader :definition_files
    end

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
        Rubotics.manifest.register_package package, *current_file
    end

    @loaded_autobuild_files = Set.new
    def self.import_autobuild_file(source, path)
        return if @loaded_autobuild_files.include?(path)

        @file_stack.push([source, File.basename(path)])
        load path
        @loaded_autobuild_files << path

    ensure
        @file_stack.pop
    end
end

def ruby_doc(pkg, target = 'doc')
    pkg.doc_task do
        pkg.doc_disabled unless File.file?('Rakefile')
        Autobuild::Subprocess.run pkg.name, 'doc', 'rake', target
    end

end

# Common setup for packages hosted on groupfiles/Autonomy
def package_common(package_type, spec)
    package_name = Rubotics.package_name_from_options(spec)

    begin
        Rake::Task[package_name]
        Rubotics.warn "#{package_name} in #{Rubotics.current_file[0]} has been overriden in #{Rubotics.definition_source(package_name)}"
    rescue
    end

    Rubotics.define(package_type, spec) do |pkg|
        pkg.srcdir   = pkg.name
        yield(pkg) if block_given?
    end
end

def cmake_package(options, &block)
    package_common(:cmake, options) do |pkg|
        Rubotics.add_build_system_dependency 'cmake'
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

# Use this method to import and build CMake packages that are hosted on the
# groupfiles server, on the autonomy project folder
def autotools_package(options, &block)
    package_common(:autotools, options) do |pkg|
        Rubotics.add_build_system_dependency 'autotools'
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

def ruby_common(pkg)
    pkg.post_install do
        Autobuild.update_environment pkg.srcdir
        if File.file?('Rakefile')
            if File.directory?('ext')
                Autobuild::Subprocess.run pkg.name, 'post-install', 'rake', 'setup'
            end
        end
    end
    Autobuild.update_environment pkg.srcdir
end

def env_set(name, value)
    Rubotics.env_set(name, value)
end
def env_add(name, value)
    Rubotics.env_add(name, value)
end

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

def orogen_package(options, &block)
    package_common(:orogen, options) do |pkg|
        yield(pkg) if block_given?
    end
end

def source_package(options)
    package_common(options) do |pkg|
        pkg.srcdir   = pkg.name
        yield(pkg) if block_given?
    end
end

def configuration_option(*opts, &block)
    Rubotics.configuration_option(*opts, &block)
end
