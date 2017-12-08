module Autoproj
    # Base implementation for the query classes {SourcePackageQuery} and {OSPackageQuery}
    class QueryBase
        # Match priorities
        EXACT = 4
        PARTIAL = 3

        # The call chain to be matched (i.e. autobuild.name becomes
        # ['autobuild', 'name']
        attr_reader :fields
        # The expected value
        attr_reader :value
        # Whether the match can be partial
        attr_predicate :partial?, true

        # @api private
        #
        # Match class that matches anything
        #
        # Use {.all}
        class All
            def match(pkg); true end
        end

        # Get a query that matches anything
        #
        # @return [All]
        def self.all
            All.new
        end

        def initialize(fields, value, partial)
            @fields = fields
            @value  = value
            @value_rx = Regexp.new(Regexp.quote(value), true)
            @partial = partial
        end

        # Checks if a package matches against the query
        #
        # @param [String] pkg the osdep package name
        # @return [Boolean] true if it does, false otherwise
        #
        # If the package matches, the returned value can be one of:
        #
        # EXACT:: this is an exact match
        # PARTIAL::
        #   the expected value can be found in the package field. The
        #   match is done in a case-insensitive way
        #
        # If partial? is not set (i.e. if FIELD=VALUE was used), then only EXACT
        # or false can be returned.
        def match(pkg)
            raise NotImplementedError
        end

        # @api private
        #
        # Parse a single field in a query (i.e. a FIELD[=~]VALUE string)
        def self.parse(str, allowed_fields: [], default_fields: Hash.new)
            if parsed = /[=~]/.match(str)
                field, value = parsed.pre_match, parsed.post_match
                partial = (parsed[0] == '~')
            else
                raise ArgumentError, "invalid query string '#{str}', expected FIELD and VALUE separated by either = or ~"
            end

            field = default_fields[field] || field

            # Validate the query key
            if !allowed_fields.include?(field)
                raise ArgumentError, "'#{field}' is not a known query key"
            end

            fields = field.split('.')
            return fields, value, partial
        end

        # Parse a complete query
        def self.parse_query(query, *args)
            query = query.split(':')
            query = query.map do |str|
                parse(str, *args)
            end
            if query.size == 1
                query.first
            else
                And.new(query)
            end
        end

        # Match object that combines multiple matches using a logical OR
        class Or
            def initialize(submatches)
                @submatches = submatches
            end
            def each_subquery(&block)
                @submatches.each(&block)
            end
            def match(pkg)
                @submatches.map { |m| m.match(pkg) }.compact.max
            end
        end

        # Match object that combines multiple matches using a logical AND
        class And
            def initialize(submatches)
                @submatches = submatches
            end
            def each_subquery(&block)
                @submatches.each(&block)
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
end

