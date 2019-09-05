require 'yaml'
module Autoproj
    YAML_LOAD_ERROR =
        if defined? Psych::SyntaxError
            Psych::SyntaxError
        else
            ArgumentError
        end

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

    # Enumerate the post-import blocks registered for the given package
    #
    # @param [PackageDefinition] pkg
    # @see post_import
    def self.each_post_import_block(pkg, &block)
        # We use Autobuild packages as keys
        pkg = pkg.autobuild if pkg.respond_to?(:autobuild)

        @post_import_blocks[nil].each(&block)
        @post_import_blocks[pkg]&.each(&block)
    end

    # Register a block that should be called after a set of package(s) have
    # been imported
    #
    # @overload post_import(&block) register the block for all packages
    # @overload post_import(*packages, &block)
    #   @param [Array<Autobuild::Package,PackageDefinition>] packages
    def self.post_import(*packages, &block)
        if packages.empty?
            @post_import_blocks[nil] << block
        else
            packages.each do |pkg|
                # We use Autobuild packages as keys
                pkg = pkg.autobuild if pkg.respond_to?(:autobuild)
                @post_import_blocks[pkg] << block
            end
        end
    end
end
