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

    def self.not_silent
        silent = Autobuild.silent?
        Autobuild.silent = false
        yield
    ensure
        Autobuild.silent = silent
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

    def self.report_interrupt(io = STDERR)
        io.puts
        io.puts color("Interrupted by user", :red, :bold)
    end

    # Subclass of Autobuild::Reporter, used to display a message when the build
    # finishes/fails.
    class Reporter < Autobuild::Reporter
        def error(error)
            error_lines = error.to_s.split("\n")
            Autoproj.not_silent do
                Autoproj.message("Command failed", :bold, :red, STDERR)
                Autoproj.message("#{error_lines.shift}", :bold, :red, STDERR)
                error_lines.each do |line|
                    Autoproj.message line, STDERR
                end
            end
        end

        def reset_timer
            @timer_start = Time.now
        end

        def elapsed_time
            return unless @timer_start
            secs = Time.now - @timer_start
            return if secs < 1

            [[60, 'sec'], [60, 'min'], [24, 'hour'], [1000, 'day']].map do |count, name|
                if secs > 0
                    secs, n = secs.divmod(count)
                    next if (val = n.to_i) == 0
                    "#{val} #{val > 1 ? name + 's' : name}"
                end
            end.compact.reverse.join(' ')
        end

        def success
            elapsed_string = elapsed_time ? " (took #{elapsed_time})" : ''
            Autoproj.message("Command finished successfully at #{Time.now}#{elapsed_string}", :bold, :green)
            if Autobuild.post_success_message
                Autoproj.message Autobuild.post_success_message
            end
        end
    end

    def self.report(root_dir: nil, silent: nil, debug: Autobuild.debug,
                    on_package_success: :report,
                    on_package_failures: Autobuild::Reporting.default_report_on_package_failures)
        reporter = Autoproj::Reporter.new
        Autobuild::Reporting << reporter
        interrupted = nil

        if !silent.nil?
            on_package_success = silent ? :silent : :report
        end
        silent_errors = [:report_silent, :exit_silent].include?(on_package_failures)

        package_failures = Autobuild::Reporting.report(on_package_failures: :report_silent) do
            begin
                reporter.reset_timer
                yield
            rescue Interrupt => e
                interrupted = e
            end
        end


        if package_failures.empty?
            if interrupted
                raise interrupted
            elsif on_package_success == :report
                Autobuild::Reporting.success
            end
            return []
        else
            Autobuild::Reporting.report_finish_on_error(
                package_failures, on_package_failures: on_package_failures, interrupted_by: interrupted)
        end

    rescue CLI::CLIException, InvalidWorkspace, ConfigError => e
        if silent_errors
            return [e]
        elsif on_package_failures == :raise
            raise e
        elsif on_package_failures == :report
            Autoproj.error e.message
            [e]
        elsif on_package_failures == :exit
            Autoproj.error e.message
            exit 1
        end

    rescue SystemExit
        raise
    ensure
        if !silent_errors && interrupted
            report_interrupt
        end

        Autobuild::Reporting.remove(reporter) if reporter
    end
end
