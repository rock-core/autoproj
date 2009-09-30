require 'autobuild'

module Rubotics
    def self.warn(message)
        STDERR.puts "WARN: #{message}"
    end

    @definition_files = Hash.new
    @file_stack       = Array.new
    class << self
        attr_reader :definition_files
    end

    #def self.definition_file(package_name)
    #    if file = @definition_files[package_name.to_str]
    #        file
    #    else
    #        "I don't know where #{package_name} has been defined"
    #    end
    #end

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

    def self.import_autobuild_file(source, path)
        @file_stack.push([source, File.basename(path)])
        load path

    ensure
        @file_stack.pop
    end

    # Loads this other source as
    def self.import_source(name)
    end
end

def import_source(name)
    Rubotics.import_source(name)
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
        unless %w{modules/logger modules/base}.include?(pkg.name)
            pkg.depends_on 'modules/logger' 
        end
        yield(pkg) if block_given?
    end
end

def source_package(options)
    package_common(options) do |pkg|
        pkg.srcdir   = pkg.name
        yield(pkg) if block_given?
    end
end

