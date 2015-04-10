module Autoproj
    # @deprecated use config.override instead
    def self.override_option(option_name, value)
        Autoproj.warn "#{__method__} is deprecated, use the API on Autoproj.config (from Autoproj::Configuration) instead"
        caller.each { |bt| Autoproj.warn "  #{bt}" }
        config.override(option_name, value)
    end
    # @deprecated use config.reset instead
    def self.reset_option(key)
        Autoproj.warn "#{__method__} is deprecated, use the API on Autoproj.config (from Autoproj::Configuration) instead"
        caller.each { |bt| Autoproj.warn "  #{bt}" }
        config.reset(key)
    end
    # @deprecated use config.set(key, value, user_validated) instead
    def self.change_option(key, value, user_validated = false)
        Autoproj.warn "#{__method__} is deprecated, use the API on Autoproj.config (from Autoproj::Configuration) instead"
        caller.each { |bt| Autoproj.warn "  #{bt}" }
        config.set(key, value, user_validated)
    end
    # @deprecated use config.validated_values instead
    def self.option_set
        Autoproj.warn "#{__method__} is deprecated, use the API on Autoproj.config (from Autoproj::Configuration) instead"
        caller.each { |bt| Autoproj.warn "  #{bt}" }
        config.validated_values
    end
    # @deprecated use config.get(key) instead
    def self.user_config(key)
        Autoproj.warn "#{__method__} is deprecated, use the API on Autoproj.config (from Autoproj::Configuration) instead"
        caller.each { |bt| Autoproj.warn "  #{bt}" }
        config.get(key)
    end
    # @deprecated use config.declare(name, type, options, &validator) instead
    def self.configuration_option(name, type, options, &validator)
        Autoproj.warn "#{__method__} is deprecated, use the API on Autoproj.config (from Autoproj::Configuration) instead"
        caller.each { |bt| Autoproj.warn "  #{bt}" }
        config.declare(name, type, options, &validator)
    end
    # @deprecated use config.declared?(name, type, options, &validator) instead
    def self.declared_option?(name)
        Autoproj.warn "#{__method__} is deprecated, use the API on Autoproj.config (from Autoproj::Configuration) instead"
        caller.each { |bt| Autoproj.warn "  #{bt}" }
        config.declared?(name)
    end
    # @deprecated use config.configure(option_name) instead
    def self.configure(option_name)
        Autoproj.warn "#{__method__} is deprecated, use the API on Autoproj.config (from Autoproj::Configuration) instead"
        caller.each { |bt| Autoproj.warn "  #{bt}" }
        config.configure(option_name)
    end
    # @deprecated use config.has_value_for?(name)
    def self.has_config_key?(name)
        Autoproj.warn "#{__method__} is deprecated, use the API on Autoproj.config (from Autoproj::Configuration) instead"
        caller.each { |bt| Autoproj.warn "  #{bt}" }
        config.has_value_for?(name)
    end
    # @deprecated use config.shell_helpers? instead
    def self.shell_helpers?
        Autoproj.warn "#{__method__} is deprecated, use the API on Autoproj.config (from Autoproj::Configuration) instead"
        caller.each { |bt| Autoproj.warn "  #{bt}" }
        config.shell_helpers?
    end
    # @deprecated use config.shell_helpers= instead
    def self.shell_helpers=(flag)
        Autoproj.warn "#{__method__} is deprecated, use the API on Autoproj.config (from Autoproj::Configuration) instead"
        caller.each { |bt| Autoproj.warn "  #{bt}" }
        config.shell_helpers = flag
    end

    def self.save_config
        Autoproj.warn "#{__method__} is deprecated, use the API on Autoproj.config (from Autoproj::Configuration) instead"
        caller.each { |bt| Autoproj.warn "  #{bt}" }
        config.save
    end

    def self.config
        workspace.config
    end

    def self.load_config
        workspace.load_config
    end

    class << self
        attr_accessor :reconfigure
    end
    def self.reconfigure?; @reconfigure end
end

