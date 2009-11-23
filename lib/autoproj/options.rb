module Autoproj
    class InputError < RuntimeError; end

    class BuildOption
        attr_reader :name
        attr_reader :type
        attr_reader :options

        attr_reader :validator

        TRUE_STRINGS = %w{on yes y true}
        FALSE_STRINGS = %w{off no n false}
        def initialize(name, type, options, validator)
            @name, @type, @options = name.to_str, type.to_str, options.to_hash
            @validator = validator.to_proc if validator
            if !BuildOption.respond_to?("validate_#{type}")
                raise ConfigError, "invalid option type #{type}"
            end
        end

        def doc
            options[:doc] || "#{name} (no documentation for this option)"
        end

        def ask(current_value)
            default_value = if current_value then current_value.to_s
                            else options[:default].to_str
                            end

            STDERR.print "  #{doc} [#{default_value}] "
            answer = STDIN.readline.chomp
            if answer == ''
                answer = default_value
            end
            validate(answer)

        rescue InputError => e
            STDERR.puts Autoproj.console.color("invalid value: #{e.message}", :red)
            retry
        end

        def validate(value)
            value = BuildOption.send("validate_#{type}", value, options)
            if validator
                value = validator[value]
            end
            value
        end

        def self.validate_boolean(value, options)
            if TRUE_STRINGS.include?(value.downcase)
                true
            elsif FALSE_STRINGS.include?(value.downcase)
                false
            else
                raise InputError, "invalid boolean value '#{value}', accepted values are '#{TRUE_STRINGS.join(", ")}' for true, and '#{FALSE_STRINGS.join(", ")} for false"
            end
        end

        def self.validate_string(value, options)
            if possible_values = options[:possible_values]
                if !possible_values.include?(value)
                    raise InputError, "invalid value '#{value}', accepted values are '#{possible_values.join(", ")}'"
                end
            end
            value
        end
    end

    @user_config = Hash.new

    def self.option_set
        @user_config.inject(Hash.new) do |h, (k, v)|
            h[k] = v.first
            h
        end
    end

    def self.change_option(key, value, user_validated = false)
        @user_config[key] = [value, user_validated]
    end

    def self.user_config(key)
        value, seen = @user_config[key]
        # All non-user options are always considered as "seen"
        seen ||= !@declared_options.has_key?(key)

        if value.nil? || (!seen && Autoproj.reconfigure?)
            value = configure(key)
        else
            if !seen
                STDERR.puts "  #{@declared_options[key].doc}: #{value}"
                @user_config[key] = [value, true]
            end
            value
        end
    end

    @declared_options = Hash.new
    def self.configuration_option(name, type, options, &validator)
        @declared_options[name] = BuildOption.new(name, type, options, validator)
    end

    def self.configure(option_name)
        if opt = @declared_options[option_name]
            if current_value = @user_config[option_name]
                current_value = current_value.first
            end
            value = opt.ask(current_value)
            @user_config[option_name] = [value, true]
            value
        else
            raise ConfigError, "undeclared option '#{option_name}'"
        end
    end

    def self.save_config
        File.open(File.join(Autoproj.config_dir, "config.yml"), "w") do |io|
            config = Hash.new
            @user_config.each_key do |key|
                config[key] = @user_config[key].first
            end

            io.write YAML.dump(config)
        end
    end

    def self.has_config_key?(name)
        @user_config.has_key?(name)
    end

    def self.load_config
        config_file = File.join(Autoproj.config_dir, "config.yml")
        if File.exists?(config_file)
            config = YAML.load(File.read(config_file))
            config.each do |key, value|
                @user_config[key] = [value, false]
            end
        end
    end

    class << self
        attr_accessor :reconfigure
    end
    def self.reconfigure?; @reconfigure end
end

