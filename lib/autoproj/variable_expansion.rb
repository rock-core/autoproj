module Autoproj
    # Expand build options in +value+.
    #
    # The method will expand in +value+ patterns of the form $NAME, replacing
    # them with the corresponding build option.
    def self.expand_environment(value)
        # Perform constant expansion on the defined environment variables,
        # including the option set
        options = Autoproj.option_set
        options.each_key do |k|
            options[k] = options[k].to_s
        end

        loop do
            new_value = Autoproj.single_expansion(value, options)
            if new_value == value
                break
            else
                value = new_value
            end
        end
        value
    end

    # Does a non-recursive expansion in +data+ of configuration variables
    # ($VAR_NAME) listed in +definitions+
    #
    # If the values listed in +definitions+ also contain configuration
    # variables, they do not get expanded
    def self.single_expansion(data, definitions)
        if !data.respond_to?(:to_str)
            return data
        end
        definitions = { 'HOME' => ENV['HOME'] }.merge(definitions)

        data = data.gsub /(.|^)\$(\w+)/ do |constant_name|
            prefix = constant_name[0, 1]
            if prefix == "\\"
                next(constant_name[1..-1])
            end
            if prefix == "$"
                prefix, constant_name = "", constant_name[1..-1]
            else
                constant_name = constant_name[2..-1]
            end

            if !(value = definitions[constant_name])
                if !(value = Autoproj.user_config(constant_name))
                    if !block_given? || !(value = yield(constant_name))
                        raise ArgumentError, "cannot find a definition for $#{constant_name}"
                    end
                end
            end
            "#{prefix}#{value}"
        end
        data
    end

    # Expand constants within +value+
    #
    # The list of constants is given in +definitions+. It raises ConfigError if
    # some values are not found
    def self.expand(value, definitions = Hash.new)
        if value.respond_to?(:to_hash)
            value.dup.each do |name, definition|
                value[name] = expand(definition, definitions)
            end
            value
        elsif value.respond_to?(:to_ary)
            value.map { |val| expand(val, definitions) }
        else
            value = single_expansion(value, definitions)
            if contains_expansion?(value)
                raise ConfigError.new, "some expansions are not defined in #{value.inspect}"
            end
            value
        end
    end

    # True if the given string contains expansions
    def self.contains_expansion?(string); string =~ /\$/ end

    def self.resolve_one_constant(name, value, result, definitions)
        result[name] = single_expansion(value, result) do |missing_name|
            result[missing_name] = resolve_one_constant(missing_name, definitions.delete(missing_name), result, definitions)
        end
    end

    # Resolves all possible variable references from +constants+
    #
    # I.e. replaces variables by their values, so that no value in +constants+
    # refers to variables defined in +constants+
    def self.resolve_constant_definitions(constants)
        constants = constants.dup
        constants['HOME'] = ENV['HOME']
        
        result = Hash.new
        while !constants.empty?
            name  = constants.keys.first
            value = constants.delete(name)
            resolve_one_constant(name, value, result, constants)
        end
        result
    end
end

