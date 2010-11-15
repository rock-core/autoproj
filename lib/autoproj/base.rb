module Autoproj
    class ConfigError < RuntimeError
        attr_accessor :file
        def initialize(file = nil)
            super
            @file = file
        end
    end
    class InternalError < RuntimeError; end

    # Yields, and if the given block raises a ConfigError with no file assigned,
    # add that file to both the object and the exception message
    def self.in_file(file, exception_t = ConfigError)
        yield

    rescue exception_t => e
        if exception_t != ConfigError
            raise ConfigError.new(file), "in #{file}: #{e.message}", e.backtrace
        elsif !e.file
            e.file = file
            raise e, "in #{file}: #{e.message}", e.backtrace
        else
            raise e
        end
    end
end


