module Autoproj
    # Match class for the query system.
    #
    # This class allows to create a query object based on a textual
    # representation, and then match packages using this query object.
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
    #   * autobuild.name: the package name
    #   * autobuild.srcdir: the package source directory
    #   * autobuild.class.name: the package class
    #   * vcs.type: the VCS type (as used in the source.yml files)
    #   * vcs.url: the URL from the VCS. The exact semantic of it depends on the
    #     VCS type
    #   * package_set.name: the name of the package set that defines the package
    #
    # Some fields have shortcuts:
    #   * 'name' can be used instead of 'autobuild.name'
    #   * 'class' can be used instead of 'autobuild.class.name'
    #   * 'vcs' can be used instead of 'vcs.url'
    #   * 'package_set' can be used instead of 'package_set.name'
    #
    class SourcePackageQuery < QueryBase
        ALLOWED_FIELDS = [
            "autobuild.name",
            "autobuild.srcdir",
            "autobuild.class.name",
            "vcs.type",
            "vcs.url",
            "package_set.name"
        ]
        DEFAULT_FIELDS = {
            "name" => "autobuild.name",
            "class" => "autobuild.class.name",
            "vcs" => "vcs.url",
            "package_set" => "package_set.name"
        }

        # Match priorities
        DIR_PREFIX_STRONG = 2
        DIR_PREFIX_WEAK = 1

        attr_predicate :use_dir_prefix?

        def initialize(fields, value, partial)
            super(fields, value, partial)

            directories = value.split("/")
            unless directories.empty?
                @use_dir_prefix = true
                rx = directories
                     .map { |d| "#{Regexp.quote(d)}\\w*" }
                     .join("/")
                rx = Regexp.new(rx, true)
                @dir_prefix_weak_rx = rx

                rx_strict = directories[0..-2]
                            .map { |d| "#{Regexp.quote(d)}\\w*" }
                            .join("/")
                rx_strict = Regexp.new("#{rx_strict}/#{Regexp.quote(directories.last)}$", true)
                @dir_prefix_strong_rx = rx_strict
            end
        end

        # Checks if +pkg+ matches the query
        #
        # Returns false if +pkg+ does not match the query and a true value
        # otherwise.
        #
        # If the package matches, the returned value can be one of:
        #
        # EXACT:: this is an exact match
        # PARTIAL::
        #   the expected value can be found in the package field. The
        #   match is done in a case-insensitive way
        # DIR_PREFIX_STRONG::
        #   if the expected value contains '/' (directory
        #   marker), the package matches the following regular
        #   expression: /el\w+/el2\w+/el3$
        # DIR_PREFIX_WEAK::
        #   if the expected value contains '/' (directory
        #   marker), the package matches the following regular
        #   expression: /el\w+/el2\w+/el3\w+
        #
        # If partial? is not set (i.e. if FIELD=VALUE was used), then only EXACT
        # or false can be returned.
        def match(pkg)
            pkg_value = fields.inject(pkg) { |v, field_name| v.send(field_name) }
            pkg_value = pkg_value.to_s

            return EXACT if pkg_value == value

            return unless partial?

            return PARTIAL if @value_rx === pkg_value

            # Special match for directories: match directory prefixes
            if use_dir_prefix?
                if @dir_prefix_strong_rx === pkg_value
                    DIR_PREFIX_STRONG
                elsif @dir_prefix_weak_rx === pkg_value
                    DIR_PREFIX_WEAK
                end
            end
        end

        # Parse a single field in a query (i.e. a FIELD[=~]VALUE string)
        def self.parse(str)
            if str !~ /[=~]/
                match_name = parse("autobuild.name~#{str}")
                match_dir  = parse("autobuild.srcdir~#{str}")
                Or.new([match_name, match_dir])
            else
                fields, value, partial =
                    super(str, default_fields: DEFAULT_FIELDS, allowed_fields: ALLOWED_FIELDS)
                new(fields, value, partial)
            end
        end
    end

    # For backward compatibility
    Query = SourcePackageQuery
end
