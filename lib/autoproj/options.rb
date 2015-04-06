module Autoproj
    # @deprecated use config.override instead
    def self.override_option(option_name, value)
        config.override(option_name, value)
    end
    # @deprecated use config.reset instead
    def self.reset_option(key)
        config.reset(key)
    end
    # @deprecated use config.set(key, value, user_validated) instead
    def self.change_option(key, value, user_validated = false)
        config.set(key, value, user_validated)
    end
    # @deprecated use config.validated_values instead
    def self.option_set
        config.validated_values
    end
    # @deprecated use config.get(key) instead
    def self.user_config(key)
        config.get(key)
    end
    # @deprecated use config.declare(name, type, options, &validator) instead
    def self.configuration_option(name, type, options, &validator)
        config.declare(name, type, options, &validator)
    end
    # @deprecated use config.declared?(name, type, options, &validator) instead
    def self.declared_option?(name)
        config.declared?(name)
    end
    # @deprecated use config.configure(option_name) instead
    def self.configure(option_name)
        config.configure(option_name)
    end
    # @deprecated use config.has_value_for?(name)
    def self.has_config_key?(name)
        config.has_value_for?(name)
    end
    # @deprecated use config.shell_helpers? instead
    def self.shell_helpers?
        config.shell_helpers?
    end
    # @deprecated use config.shell_helpers= instead
    def self.shell_helpers=(flag)
        config.shell_helpers = flag
    end

    def self.save_config
        config.save(File.join(Autoproj.config_dir, "config.yml"))
    end

    def self.config
        @config ||= Configuration.new
    end

    def self.load_config
        config_file = File.join(Autoproj.config_dir, "config.yml")
        if File.exists?(config_file)
            config.load(config_file, reconfigure?)
        end
    end

    class << self
        attr_accessor :reconfigure
    end
    def self.reconfigure?; @reconfigure end
end

