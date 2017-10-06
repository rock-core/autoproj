require 'autobuild/reporting'
module Autoproj
    class << self
        attr_accessor :verbose
        def silent?
            Autobuild.silent?
        end
        def silent=(value)
            Autobuild.silent = value
        end
    end
    @verbose = false

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

    def self.report(root_dir: nil, silent: false, debug: Autobuild.debug,
                    on_package_failures: Autobuild::Reporting.default_report_on_package_failures)
        reporter = Autoproj::Reporter.new
        Autobuild::Reporting << reporter
        package_failures = Autobuild::Reporting.report(on_package_failures: on_package_failures) do
            yield
        end
        if !silent && !package_failures.empty?
            Autobuild::Reporting.success
        end

    rescue Interrupt
        STDERR.puts
        STDERR.puts Autobuild.color("Interrupted by user", :red, :bold)
        if on_package_failures == :raise then raise
        else exit 1
        end
    rescue SystemExit
        raise
    rescue Exception => e
        STDERR.puts
        STDERR.puts Autobuild.color(e.message, :red, :bold)
        if root_dir = root_dir
            root_dir = /#{Regexp.quote(root_dir)}(?!\/\.gems)/
            e.backtrace.find_all { |path| path =~ root_dir }.
                each do |path|
                    STDERR.puts Autobuild.color("  in #{path}", :red, :bold)
                end
        end
        if on_package_failures == :raise then raise
        else exit 1
        end
    ensure
        Autobuild::Reporting.remove(reporter) if reporter
    end
end

