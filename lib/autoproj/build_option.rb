module Autoproj
    class InputError < RuntimeError; end

    # Definition of an autoproj option as defined by
    # {Configuration#declare}
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
                raise ConfigError.new, "invalid option type #{type}"
            end
        end

        def short_doc
            if short_doc = options[:short_doc]
                short_doc
            elsif doc = options[:doc]
                if doc.respond_to?(:to_ary) then doc.first
                else doc
                end
            else "#{name} (no documentation for this option)"
            end
        end

        def doc
            doc = (options[:doc] || "#{name} (no documentation for this option)")
            if doc.respond_to?(:to_ary) # multi-line
                first_line = doc[0]
                remaining = doc[1..-1]
                if remaining.empty?
                    first_line
                else
                    remaining = remaining.join("\n").split("\n").join("\n    ")
                    Autoproj.color(first_line, :bold) + "\n    " + remaining
                end
            else
                doc
            end
        end

        def ask(current_value, doc = nil)
            default_value =
		if !current_value.nil? then current_value.to_s
		elsif options[:default] then options[:default].to_str
		else ''
		end

            STDOUT.print "  #{doc || self.doc} [#{default_value}] "
            STDOUT.flush
            answer = STDIN.readline.chomp
            if answer == ''
                answer = default_value
            end
            validate(answer)

        rescue InputError => e
            Autoproj.message("invalid value: #{e.message}", :red)
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
                if options[:lowercase]
                    value = value.downcase
                elsif options[:uppercase]
                    value = value.upcase
                end

                if !possible_values.include?(value)
                    raise InputError, "invalid value '#{value}', accepted values are '#{possible_values.join("', '")}' (without the quotes)"
                end
            end
            value
        end
    end
end

