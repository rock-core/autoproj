module Autoproj
    class Query
        ALLOWED_FIELDS = [
            'autobuild.name',
            'autobuild.srcdir',
            'autobuild.class.name',
            'vcs.type',
            'vcs.url',
            'package_set.name'
        ]
        DEFAULT_FIELDS = {
            'class' => 'autobuild.class.name',
            'autobuild' => 'autobuild.name',
            'vcs' => 'vcs.url',
            'package_set' => 'package_set.name'
        }

        # Match priorities
        EXACT = 4
        PARTIAL = 3
        DIR_PREFIX_STRONG = 2
        DIR_PREFIX_WEAK = 1

        attr_reader :fields
        attr_reader :value
        attr_predicate :use_dir_prefix?

        def initialize(fields, value)
            @fields = fields
            @value = value
            @value_rx = Regexp.new(Regexp.quote(value), true)

            directories = value.split('/')
            if !directories.empty?
                @use_dir_prefix = true
                rx = directories.
                    map { |d| "#{Regexp.quote(d)}\\w*" }.
                    join("/")
                rx = Regexp.new(rx, true)
                @dir_prefix_weak_rx = rx

                rx_strict = directories[0..-2].
                    map { |d| "#{Regexp.quote(d)}\\w*" }.
                    join("/")
                rx_strict = Regexp.new("#{rx_strict}/#{Regexp.quote(directories.last)}$", true)
                @dir_prefix_strong_rx = rx_strict
            end
        end

        def match(pkg)
            pkg_value = fields.inject(pkg) { |v, field_name| v.send(field_name) }
            pkg_value = pkg_value.to_s

            if pkg_value == value
                return EXACT
            elsif pkg_value =~ @value_rx
                return PARTIAL
            end

            # Special match for directories: match directory prefixes
            if use_dir_prefix?
                if pkg_value =~ @dir_prefix_strong_rx
                    return DIR_PREFIX_STRONG
                elsif pkg_value =~ @dir_prefix_weak_rx
                    return DIR_PREFIX_WEAK
                end
            end
        end

        def self.parse(str)
            field, value = str.split('=')
            if DEFAULT_FIELDS[field]
                field = DEFAULT_FIELDS[field]
            end

            # Validate the query key
            if !ALLOWED_FIELDS.include?(field)
                raise ArgumentError, "#{field} is not a known query key"
            end

            fields = field.split('.')
            new(fields, value)
        end

        def self.parse_query(query)
            query = query.split(':')
            query = query.map do |str|
                if str !~ /=/
                    match_name = Query.parse("autobuild.name=#{str}")
                    match_dir  = Query.parse("autobuild.srcdir=#{str}")
                    Or.new([match_name, match_dir])
                else
                    Query.parse(str)
                end
            end
            And.new(query)
        end
    end

    class Or
        def initialize(submatches)
            @submatches = submatches
        end
        def match(pkg)
            @submatches.map { |m| m.match(pkg) }.compact.max
        end
    end

    class And
        def initialize(submatches)
            @submatches = submatches
        end
        def match(pkg)
            matches = @submatches.map do |m|
                if p = m.match(pkg)
                    p
                else return
                end
            end
            matches.min
        end
    end
end

