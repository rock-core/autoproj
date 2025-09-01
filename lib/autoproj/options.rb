module Autoproj
    # @deprecated use config.override instead
    def self.override_option(option_name, value)
        Autoproj.warn_deprecated __method__, "use the API on Autoproj.config (from Autoproj::Configuration) instead"
        config.override(option_name, value)
    end

    # @deprecated use config.reset instead
    def self.reset_option(key)
        Autoproj.warn_deprecated __method__, "use the API on Autoproj.config (from Autoproj::Configuration) instead"
        config.reset(key)
    end

    # @deprecated use config.set(key, value, user_validated) instead
    def self.change_option(key, value, user_validated = false)
        Autoproj.warn_deprecated __method__, "use the API on Autoproj.config (from Autoproj::Configuration) instead"
        config.set(key, value, user_validated)
    end

    # @deprecated use config.validated_values instead
    def self.option_set
        Autoproj.warn_deprecated __method__, "use the API on Autoproj.config (from Autoproj::Configuration) instead"
        config.validated_values
    end

    # @deprecated use config.get(key) instead
    def self.user_config(key)
        Autoproj.warn_deprecated __method__, "use the API on Autoproj.config (from Autoproj::Configuration) instead"
        config.get(key)
    end

    # @deprecated use config.declare(name, type, options, &validator) instead
    def self.configuration_option(name, type, **options, &validator)
        Autoproj.warn_deprecated __method__, "use the API on Autoproj.config (from Autoproj::Configuration) instead"
        config.declare(name, type, **options, &validator)
    end

    # @deprecated use config.declared?(name, type, options, &validator) instead
    def self.declared_option?(name)
        Autoproj.warn_deprecated __method__, "use the API on Autoproj.config (from Autoproj::Configuration) instead"
        config.declared?(name)
    end

    # @deprecated use config.configure(option_name) instead
    def self.configure(option_name)
        Autoproj.warn_deprecated __method__, "use the API on Autoproj.config (from Autoproj::Configuration) instead"
        config.configure(option_name)
    end

    # @deprecated use config.has_value_for?(name)
    def self.has_config_key?(name)
        Autoproj.warn_deprecated __method__, "use the API on Autoproj.config (from Autoproj::Configuration) instead"
        config.has_value_for?(name)
    end

    # @deprecated use config.shell_helpers? instead
    def self.shell_helpers?
        Autoproj.warn_deprecated __method__, "use the API on Autoproj.config (from Autoproj::Configuration) instead"
        config.shell_helpers?
    end

    # @deprecated use config.shell_helpers= instead
    def self.shell_helpers=(flag)
        Autoproj.warn_deprecated __method__, "use the API on Autoproj.config (from Autoproj::Configuration) instead"
        config.shell_helpers = flag
    end

    def self.save_config
        Autoproj.warn_deprecated __method__, "use the API on Autoproj.config (from Autoproj::Configuration) instead"
        config.save
    end

    def self.load_config
        workspace.load_config
    end

    class << self
        attr_accessor :reconfigure
    end
    def self.reconfigure?
        @reconfigure
    end
end
