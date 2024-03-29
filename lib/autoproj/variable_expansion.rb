module Autoproj
    # Flattens a hash whose keys are strings and values are either plain values,
    # arrays or hashes
    #
    # The keys in the flattened hash are made hierarchical by appending ".".
    # Array values are ignored.
    #
    # @example
    #    h = Hash['test' => 10, 'h' => Hash['value' => '20']]
    #    options_to_flat_hash(h)
    #    # Hash['test' => '10',
    #    #      'h.value' => 20]
    #
    #
    # @param [{[String,Symbol]=>[String,Numeric,Array,Hash]}]
    # @return [{String=>String}]
    def self.flatten_recursive_hash(hash, prefix = "")
        result = Hash.new
        hash.each do |k, v|
            if v.kind_of?(Hash)
                result.merge!(flatten_recursive_hash(v, "#{prefix}#{k}."))
            elsif !v.respond_to?(:to_ary)
                result["#{prefix}#{k}"] = v.to_s
            end
        end
        result
    end

    # Does a non-recursive expansion in +data+ of configuration variables
    # ($VAR_NAME) listed in +definitions+
    #
    # If the values listed in +definitions+ also contain configuration
    # variables, they do not get expanded
    def self.single_expansion(data, definitions)
        return data unless data.respond_to?(:to_str)

        data = data.gsub(/(.|^)\$(\w+)/) do |constant_name|
            prefix = constant_name[0, 1]
            next(constant_name[1..-1]) if prefix == "\\"

            if prefix == "$"
                prefix = ""
                constant_name = constant_name[1..-1]
            else
                constant_name = constant_name[2..-1]
            end

            value = definitions[constant_name]
            if value.nil?
                if !block_given? || !(value = yield(constant_name))
                    raise ArgumentError, "cannot find a definition for $#{constant_name}"
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
    def self.contains_expansion?(string)
        string.respond_to?(:to_str) && string.to_str =~ /\$/
    end

    def self.resolve_one_constant(name, value, result, definitions)
        result[name] ||= single_expansion(value, result) do |missing_name|
            result[missing_name] =
                resolve_one_constant(missing_name, definitions[missing_name], result, definitions)
        end
    end

    # Resolves all possible variable references from +constants+
    #
    # I.e. replaces variables by their values, so that no value in +constants+
    # refers to variables defined in +constants+
    def self.resolve_constant_definitions(constants, definitions = Hash.new)
        definitions = definitions.merge(constants)

        all_resolutions = Hash.new
        resolution_cache = Hash.new
        constants.each do |key, value|
            all_resolutions[key] = resolve_one_constant(key, value, resolution_cache, definitions)
        end
        all_resolutions
    end
end
