module Autoproj
    # Match class to query OS packages
    #
    # This class allows to create a query object based on a textual
    # representation, and then match osdeps packages using this query object.
    #
    # The queries are of the form
    #
    #   FIELD=VALUE:FIELD~VALUE:FIELD=VALUE
    #
    # The F=V form requires an exact match while F~V allows partial
    # matches. The different matches are combined with AND (i.e. only packages
    # matching all criterias will be returned)
    #
    # The following fields are allowed:
    #   * name: the osdep name
    #   * real_package: a regexp that matches the name of the underlying package
    #   * package_manager: a regexp that matches the underlying package manager
    #
    class OSPackageQuery < QueryBase
        ALLOWED_FIELDS = %w[
            name
            real_package
            package_manager
        ]
        DEFAULT_FIELDS = {
        }

        def initialize(fields, value, partial, os_package_resolver)
            super(fields, value, partial)
            @os_package_resolver = os_package_resolver
        end

        class Adapter
            def initialize(pkg, os_package_resolver)
                @pkg = pkg
                @os_package_resolver = os_package_resolver
            end

            def name
                [@pkg]
            end

            def real_package
                packages = @os_package_resolver.resolve_os_packages([@pkg])
                packages.flat_map do |handler, handler_packages|
                    handler_packages
                end.uniq
            end

            def package_manager
                packages = @os_package_resolver.resolve_os_packages([@pkg])
                packages.flat_map do |handler, handler_packages|
                    handler
                end.uniq
            end
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
            pkg = Adapter.new(pkg, @os_package_resolver)
            pkg_value = fields.inject(pkg) do |v, field_name|
                v.send(field_name)
            end

            return EXACT if pkg_value.include?(value)

            return unless partial?

            PARTIAL if pkg_value.any? { |v| @value_rx === v }
        end

        # Parse a single field in a query (i.e. a FIELD[=~]VALUE string)
        def self.parse(str, os_package_resolver)
            fields, value, partial =
                super(str, allowed_fields: ALLOWED_FIELDS)
            OSPackageQuery.new(fields, value, partial, os_package_resolver)
        end
    end
end
