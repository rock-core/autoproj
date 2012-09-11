require 'yaml'
module Autoproj
    YAML_LOAD_ERROR =
        if defined? Psych::SyntaxError
            Psych::SyntaxError
        else
            ArgumentError
        end
            
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

    @post_import_blocks = Hash.new { |h, k| h[k] = Array.new }
    class << self
        attr_reader :post_import_blocks
    end

    def self.each_post_import_block(pkg, &block)
        @post_import_blocks[nil].each(&block)
        if @post_import_blocks.has_key?(pkg)
            @post_import_blocks[pkg].each(&block)
        end
    end

    def self.post_import(*packages, &block)
        if packages.empty?
            @post_import_blocks[nil] << block
        else
            packages.each do |pkg|
                @post_import_blocks[pkg] << block
            end
        end
    end
end

