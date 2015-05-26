require 'autobuild/reporting'
module Autoproj
    class << self
        attr_accessor :verbose
        attr_reader :console
        def silent?
            Autobuild.silent?
        end
        def silent=(value)
            Autobuild.silent = value
        end
    end
    @verbose = false
    @console = HighLine.new
	

    def self.silent(&block)
        Autobuild.silent(&block)
    end

    def self.message(*args)
        Autobuild.message(*args)
    end

    def self.color(*args)
        Autobuild.color(*args)
    end

    # Displays an error message
    def self.error(message)
        Autobuild.error(message)
    end

    # Displays a warning message
    def self.warn(message, *style)
        Autobuild.warn(message, *style)
    end

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

    def self.report(options = Hash.new)
        options = Kernel.validate_options options,
            root_dir: nil,
            silent: false

        Autobuild::Reporting.report do
            yield
        end
        if !options[:silent]
            Autobuild::Reporting.success
        end

    rescue Interrupt
        STDERR.puts
        STDERR.puts Autobuild.color("Interrupted by user", :red, :bold)
        if Autobuild.debug then raise
        else exit 1
        end
    rescue Exception => e
        STDERR.puts
        STDERR.puts Autobuild.color(e.message, :red, :bold)
        if root_dir = options[:root_dir]
            root_dir = /#{Regexp.quote(root_dir)}(?!\/\.gems)/
            e.backtrace.find_all { |path| path =~ root_dir }.
                each do |path|
                    STDERR.puts Autobuild.color("  in #{path}", :red, :bold)
                end
        end
        if Autobuild.debug then raise
        else exit 1
        end
    end
end

