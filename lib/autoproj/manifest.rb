require "yaml"
require "csv"
require "utilrb/kernel/options"
require "set"

if RbConfig::CONFIG["host_os"] =~ %r{(msdos|mswin|djgpp|mingw|[Ww]indows)}
    require "win32/dir"
end

module Autoproj
    # The Manifest class represents the information included in the main
    # manifest file, and allows to manipulate it
    class Manifest
        # Set the package sets that are available on this manifest
        #
        # This is set externally at loading time. {load_and_update_package_sets}
        # can do it as well
        #
        # @return [Array<PackageSet>]
        attr_writer :package_sets

        # Loads the manifest file located at +file+ and returns the Manifest
        # instance that represents it
        def self.load(file)
            manifest = Manifest.new
            manifest.load(file)
            manifest
        end

        # A normalized version of the layout as represented in the manifest file
        #
        # It is a mapping from a selection name into the layout level it is
        # defined in. For instance:
        #
        #     layout:
        #     - subdir:
        #       - pkg/in/subdir
        #     - pkg/in/root
        #
        # Would be normalized as
        #
        #     'pkg/in/subdir' => '/subdir/',
        #     'pkg/in/root' => '/'
        #
        # Note that these are only strings. There is no normalization against
        # package names or metapackages.
        #
        # This is computed by {#compute_normalized_layout}
        #
        # @return [Hash]
        attr_reader :normalized_layout

        # Load the manifest data contained in +file+
        def load(file)
            unless File.exist?(file)
                raise ConfigError.new(File.dirname(file)),
                      "expected an autoproj configuration in #{File.dirname(file)}, "\
                      "but #{file} does not exist"
            end

            data = Autoproj.in_file(file, Autoproj::YAML_LOAD_ERROR) do
                YAML.safe_load(File.read(file)) || {}
            end

            if data["layout"]&.member?(nil)
                Autoproj.warn "There is an empty entry in your layout in #{file}. All empty entries are ignored."
                data["layout"] = data["layout"].compact
            end

            @file = file
            initialize_from_hash(data)
        end

        # @api private
        #
        # Initialize the manifest from a hash, as loaded from a manifest file
        def initialize_from_hash(data)
            @data = data
            @ignored_packages |= (data["ignored_packages"] || Set.new).to_set
            @ignored_packages |= (data["ignore_packages"] || Set.new).to_set
            invalidate_ignored_package_names
            @manifest_exclusions |= (data["exclude_packages"] || Set.new).to_set

            normalized_layout = Hash.new
            compute_normalized_layout(
                normalized_layout,
                "/",
                data["layout"] || Hash.new
            )
            @normalized_layout = normalized_layout
            @has_layout = !!data["layout"]

            if data["constants"]
                @constant_definitions =
                    Autoproj.resolve_constant_definitions(data["constants"])
            end
        end

        # Make an empty layout
        #
        # Unless the default layout (that you can get with {#remove_layout}), this
        # means that no package is selected by default
        def clear_layout
            @has_layout = true
            normalized_layout.clear
        end

        # Remove the layout
        #
        # Unlike {#clear_layout}, this means that all defined source packages
        # will be selected by default
        def remove_layout
            @has_layout = false
            normalized_layout.clear
        end

        # Add a package into the layout
        def add_package_to_layout(package)
            package_name = validate_package_name_argument(package)
            @has_layout = true
            normalized_layout[package_name] = "/"
        end

        # Add a package into the layout
        def add_package_set_to_layout(package_set)
            validate_package_set_in_self(package_set)
            add_metapackage_to_layout(package_set.metapackage)
        end

        # Add a metapackage into the layout
        def add_metapackage_to_layout(metapackage)
            validate_metapackage_in_self(metapackage)
            @has_layout = true
            normalized_layout[metapackage.name] = "/"
        end

        # Add a constant definition, used when resolving $CONSTANT in loaded
        # files
        def add_constant_definition(key, value)
            constant_definitions[key] = value
        end

        # The manifest data as a Hash
        attr_reader :data

        # The set of packages defined so far as a mapping from package name to
        # [Autobuild::Package, package_set, file] tuple
        attr_reader :packages

        # The path to the manifest file that has been loaded
        attr_reader :file

        # The set of package names for packages that should be ignored
        attr_reader :ignored_packages

        # A set of other autoproj installations that are being reused
        attr_reader :reused_installations

        # Whether {#resolve_package_name} should raise if an osdep is found that
        # is not available on the current operating system, or simply return it
        #
        # @return [Boolean]
        def accept_unavailable_osdeps?
            !!@accept_unavailable_osdeps
        end

        # Sets {#accept_unavailable_osdeps?}
        attr_writer :accept_unavailable_osdeps

        attr_reader :constant_definitions

        attr_reader :metapackages

        # The VCS object for the main configuration itself
        #
        # @return [VCSDefinition]
        attr_accessor :vcs

        # The definition of all OS packages available on this installation
        attr_reader :os_package_resolver

        # Whether there is a layout specified
        #
        # This is used to disambiguate between an empty layout (which would
        # build nothing) and no layout at all
        attr_predicate :has_layout?

        def initialize(ws, os_package_resolver: OSPackageResolver.new)
            @ws = ws
            @vcs = VCSDefinition.none
            @file = nil
            @data = Hash.new
            @has_layout = false
            @normalized_layout = Hash.new
            @packages = Hash.new
            @package_sets = []
            @os_package_resolver = os_package_resolver
            # Cache for #ignored?
            @ignored_package_names = nil

            @automatic_exclusions = Hash.new
            @constants_definitions = Hash.new
            @moved_packages = Hash.new
            @osdeps_overrides = Hash.new
            @metapackages = Hash.new
            @ignored_os_packages = Set.new
            @reused_installations = Array.new
            @ignored_packages = Set.new
            @manifest_exclusions = Set.new
            @accept_unavailable_osdeps = false

            @constant_definitions = Hash.new
            @package_sets << LocalPackageSet.new(ws)
        end

        # @api private
        #
        # Validate that the given metapackage object is defined in self
        def validate_metapackage_in_self(metapackage)
            if find_metapackage(metapackage.name) != metapackage
                raise UnregisteredPackage, "#{metapackage.name} is not registered on #{self}"
            end
        end

        # @api private
        #
        # Validate that the given package object is defined in self
        def validate_package_in_self(package)
            if !package.respond_to?(:autobuild)
                raise ArgumentError, "expected a PackageDefinition object but got an Autobuild package"
            elsif find_package_definition(package.name) != package
                raise UnregisteredPackage, "#{package.name} is not registered on #{self}"
            end
        end

        # @api private
        #
        # Massage an argument that should be interpreted as a package name
        def validate_package_name_argument(package, require_existing: true)
            if package.respond_to?(:name)
                validate_package_in_self(package)
                package.name
            else
                package = package.to_str
                if require_existing && !has_package?(package)
                    raise PackageNotFound, "no package named #{package} in #{self}"
                end

                package
            end
        end

        # @api private
        #
        # Validate that the given package object is defined in self
        def validate_package_set_in_self(package_set)
            if find_package_set(package_set.name) != package_set
                raise UnregisteredPackageSet, "#{package_set.name} is not registered on #{self}"
            end
        end

        # Call this method to ignore a specific package. It must not be used in
        # init.rb, as the manifest is not yet loaded then
        def ignore_package(package)
            invalidate_ignored_package_names
            @ignored_packages << validate_package_name_argument(package, require_existing: false)
        end

        # True if the given package should not be built, with the packages that
        # depend on him have this dependency met.
        #
        # This is useful if the packages are already installed on this system.
        def ignored?(package)
            package_name = validate_package_name_argument(package)
            cache_ignored_package_names.include?(package_name)
        end

        # @api private
        #
        # The list of packages that are ignored
        #
        # Do not use directly, use {#ignored?} instead
        def cache_ignored_package_names
            return @ignored_package_names if @ignored_package_names

            @ignored_package_names = each_package_definition.find_all do |pkg|
                ignored_packages.any? do |l|
                    (pkg.name == l) ||
                        ((pkg_set = metapackages[l]) && pkg_set.include?(pkg))
                end
            end.map(&:name).to_set
        end

        # @api private
        #
        # Invalidate the cache computed by {#cache_ignored_package_names}
        def invalidate_ignored_package_names
            @ignored_package_names = nil
        end

        # Enumerates the package names of all ignored packages
        #
        # @yieldparam [Autobuild::Package]
        def each_ignored_package
            return enum_for(__method__) unless block_given?

            cache_ignored_package_names.each do |pkg_name|
                yield(find_autobuild_package(pkg_name))
            end
        end

        # Removes all registered ignored packages
        def clear_ignored
            invalidate_ignored_package_names
            ignored_packages.clear
        end

        # True if the given package should not be built and its dependencies
        # should be considered as met.
        #
        # This is useful to avoid building packages that are of no use for the
        # user.
        def excluded?(package_name)
            package_name = validate_package_name_argument(package_name)

            if !explicitely_selected_in_layout?(package_name) && excluded_in_manifest?(package_name)
                true
            elsif automatic_exclusions.any? { |pkg_name,| pkg_name == package_name }
                true
            else
                false
            end
        end

        # Enumerates the package names of all ignored packages
        def each_excluded_package
            return enum_for(__method__) unless block_given?

            each_autobuild_package do |pkg|
                yield(pkg) if excluded?(pkg.name)
            end
        end

        # Removes all registered exclusions
        def clear_exclusions
            automatic_exclusions.clear
            manifest_exclusions.clear
        end

        # The set of package names that are listed in the excluded_packages
        # section of the manifest
        attr_reader :manifest_exclusions

        # A package_name => reason map of the exclusions added with {#exclude_package}
        # Exclusions listed in the manifest file are returned by #manifest_exclusions
        attr_reader :automatic_exclusions

        # @deprecated use {#exclude_package} instead
        def add_exclusion(package_name, reason)
            Autoproj.warn_deprecated __method__, "use #exclude_package instead"
            exclude_package(package_name, reason)
        end

        # Exclude +package_name+ from the build. +reason+ is a string describing
        # why the package is to be excluded.
        def exclude_package(package_name, reason)
            package = validate_package_name_argument(
                package_name, require_existing: false
            )
            if (meta = find_metapackage(package))
                meta.each_package do |pkg|
                    automatic_exclusions[pkg.name] =
                        "#{meta.name} is an excluded metapackage, "\
                        "and it includes #{pkg.name}: #{reason}"
                end
            else
                automatic_exclusions[package] = reason
            end
        end

        # Tests whether the given package is excluded in the manifest
        def excluded_in_manifest?(package_name)
            package_name = validate_package_name_argument(package_name)
            manifest_exclusions.any? do |matcher|
                if (pkg_set = metapackages[matcher]) && pkg_set.include?(package_name)
                    true
                else
                    Regexp.new(matcher) === package_name
                end
            end
        end

        # If +package_name+ is excluded from the build, returns a string that
        # tells why. Otherwise, returns nil
        #
        # Packages can either be excluded because their name is listed in the
        # exclude_packages section of the manifest, or because they are
        # disabled on this particular operating system.
        def exclusion_reason(package_name)
            package_name = validate_package_name_argument(package_name)
            if (message = automatic_exclusions[package_name])
                return message
            end

            unless explicitely_selected_in_layout?(package_name)
                manifest_exclusions.each do |matcher|
                    if (pkg_set = metapackages[matcher]) && pkg_set.include?(package_name)
                        return "#{pkg_set.name} is a metapackage listed in the exclude_packages section of the manifest, and it includes #{package_name}"
                    elsif Regexp.new(matcher) === package_name
                        return "#{package_name} is listed in the exclude_packages section of the manifest"
                    end
                end
            end
            nil
        end

        # Returns true if the given package name has been explicitely added to
        # the layout (not indirectly)
        #
        # @param [String] package_name
        # @return [Boolean]
        def explicitely_selected_in_layout?(package_name)
            package_name = package_name.to_str
            normalized_layout.has_key?(package_name)
        end

        # True if some of the sources are remote sources
        def has_remote_package_sets?
            each_remote_package_set.any? { true }
        end

        # Like #each_package_set, but filters out local package sets
        def each_remote_package_set
            return enum_for(__method__) unless block_given?

            each_package_set do |pkg_set|
                yield(pkg_set) unless pkg_set.local?
            end
        end

        # Lists all package sets defined in this manifest, including the package
        # sets that are auto-imported
        #
        # Note that this can be called only after the package sets got loaded
        # with {load_package_sets}
        #
        # @yieldparam [PackageSet]
        def each_package_set(&block)
            @package_sets.each(&block)
        end

        # Reset the list of package sets
        def reset_package_sets
            @package_sets.clear
        end

        # Registers a new package set
        #
        # @param [PackageSet] pkg_set the package set object
        def register_package_set(pkg_set)
            invalidate_ignored_package_names
            metapackage(pkg_set.name)
            metapackage("#{pkg_set.name}.all")
            @package_sets << pkg_set
        end

        # Register a new package
        #
        # @param [Autobuild::Package] package
        # @param [#call,nil] block a setup block
        # @param [PackageSet] package_set the package set that defines the package
        # @param [String] file the file in which the package is defined
        # @return [PackageDefinition]
        def register_package(package, block = nil, package_set = main_package_set, file = nil)
            invalidate_ignored_package_names
            pkg = PackageDefinition.new(package, package_set, file)
            pkg.add_setup_block(block) if block
            @packages[package.name] = pkg
            metapackage pkg.package_set.name, pkg.autobuild
            metapackage "#{pkg.package_set.name}.all", pkg.autobuild
            pkg
        end

        # The autoproj description of a package by its name
        #
        # @param [String,#name] name the package name
        # @return [PackageDefinition,nil]
        def find_package_definition(name)
            packages[validate_package_name_argument(name, require_existing: false)]
        end

        # @deprecated use {#find_package_definition}(pkg_name).package_set
        # instead
        def definition_source(name)
            Autoproj.warn_deprecated __method__, "use #package_definition_by_name(name).package_set instead"
            package_definition_by_name(name).package_set
        end

        # @deprecated use {#find_package_definition}(pkg_name).package_set
        # instead
        def definition_package_set(name)
            Autoproj.warn_deprecated __method__, "use #package_definition_by_name(name).package_set instead"
            package_definition_by_name(name).package_set
        end

        # @deprecated use {#find_package_definition} instead
        def package(name)
            Autoproj.warn_deprecated "Manifest#package is deprecated, use #package_definition_by_name instead"
            find_package_definition(name)
        end

        # Resolve a package definition by name
        #
        # Unlike {#find_package_definition}, raise if the package does not exist
        def package_definition_by_name(name)
            unless (pkg = find_package_definition(name))
                raise ArgumentError, "no package defined named '#{name}'"
            end

            pkg
        end

        # The autobuild description of a package by its name
        #
        # @param [String,#name] name the package name
        # @return [Autobuild::Package,nil]
        def find_autobuild_package(name)
            find_package_definition(name)&.autobuild
        end

        # Lists all defined packages
        #
        # @yieldparam [PackageDefinition] pkg
        def each_package_definition(&block)
            return enum_for(__method__) unless block_given?

            packages.each_value(&block)
        end

        # Lists the autobuild objects for all defined packages
        #
        # @yieldparam [Autobuild::Package] pkg
        def each_autobuild_package
            return enum_for(__method__) unless block_given?

            each_package_definition { |pkg| yield(pkg.autobuild) }
        end

        # @overload importer_definition_for(package, mainline: nil, require_existing: true, package_set: nil)
        #
        # @param [PackageDefinition] package the name of the package to be resolved
        # @param [PackageSet,nil] mainline the reference package set for which
        #   we want to compute the importer definition. Pass package.package_set
        #   if you want to avoid applying any override
        # @return [VCSDefinition] the VCS definition object
        def importer_definition_for(package, _package_set = nil, mainline: nil, require_existing: true, package_set: nil)
            if _package_set
                Autoproj.warn_deprecated "calling #importer_definition_for with the package set as second argument is deprecated, use the package_set: keyword argument instead"
                require_existing = false
            end
            package_name = validate_package_name_argument(package, require_existing: require_existing)
            package_set = _package_set || package_set || package.package_set
            mainline = package_set if mainline == true

            # package_name is already validated, do not re-validate
            vcs = package_set.importer_definition_for(package_name, require_existing: false)

            package_sets = each_package_set.to_a.dup
            index = package_sets.find_index(package_set)
            unless index
                raise RuntimeError, "found inconsistency: package #{package_name} is not in a package set of #{self}"
            end

            return vcs if package_sets[0, index + 1].include?(mainline)

            # Then apply the overrides
            package_sets[(index + 1)..-1].inject(vcs) do |updated_vcs, pkg_set|
                updated_vcs = pkg_set.overrides_for(package_name, updated_vcs, require_existing: false)
                return updated_vcs if pkg_set == mainline

                updated_vcs
            end
        end

        # Sets up the package importers based on the information listed in
        # the source's source.yml
        #
        # The priority logic is that we take the package sets one by one in the
        # order listed in the autoproj main manifest, and first come first used.
        #
        # A set that defines a particular package in its autobuild file
        # *must* provide the corresponding VCS line in its source.yml file.
        # However, it is possible for a source that does *not* define a package
        # to override the VCS
        #
        # In other words: if package P is defined by source S1, and source S0
        # imports S1, then
        #  * S1 must have a VCS line for P
        #  * S0 can have a VCS line for P, which would override the one defined
        #    by S1
        def load_importers(mainline: nil)
            packages.each_value do |pkg|
                package_mainline =
                    if mainline == true
                        pkg.package_set
                    else
                        mainline
                    end
                vcs = importer_definition_for(pkg, mainline: package_mainline)

                if vcs.none?
                    if pkg.package_set.importer_definition_for(pkg).none?
                        if (pkg.package_set != main_package_set) || !File.exist?(pkg.autobuild.srcdir)
                            raise ConfigError.new, "package set #{pkg.package_set.name} defines the package '#{pkg.name}', but does not provide a version control definition for it"
                        end
                    end
                end

                pkg.vcs = vcs
                pkg.autobuild.importer = vcs.create_autobuild_importer
            end
        end

        # Checks if there is a package with a given name
        #
        # @param [String] name the name of a source or osdep package
        # @return [Boolean]
        def has_package?(name)
            packages.has_key?(name) || os_package_resolver.include?(name)
        end

        # Checks if there is a package set with a given name
        def has_package_set?(name)
            !!find_package_set(name)
        end

        # Returns a package set from its name
        def find_package_set(name)
            each_package_set.find { |set| set.name == name }
        end

        # The PackageSet object for the given package set
        #
        # @return [PackageSet] the package set
        # @raise [ArgumentError] if none exists with that name
        def package_set(name)
            unless (set = find_package_set(name))
                raise ArgumentError, "no package set called #{name} exists"
            end

            set
        end

        # The root package set, which represents the workspace itself
        def main_package_set
            each_package_set.find(&:main?)
        end

        # Resolves a name into a set of source and osdep packages
        #
        # @param [String] name the name to be resolved. It can either be the
        # name of a source package, an osdep package or a metapackage (e.g.
        # package set).
        #
        # @return [nil,Array] either nil if there is no such osdep, or a list of
        #   (type, package_name) pairs where type is either :package or :osdeps and
        #   package_name the corresponding package name
        # @raise [PackageNotFound] if the given package name cannot be resolved
        #   into a package. If {#accept_unavailable_osdeps?} is false (the
        #   default), the exception will be raised if the package is known to be
        #   an osdep, but it is not available on the local operating system (as
        #   defined by {#os_package_resolver}), and there has been no source
        #   fallback defined with {#add_osdeps_overrides}. If true, it will
        #   return such a package as an osdep.
        def resolve_package_name(name, include_unavailable: false)
            pkg_names =
                if (pkg_set = find_metapackage(name))
                    pkg_set.each_package.map(&:name)
                else
                    [name.to_str]
                end

            result = []
            pkg_names.each do |pkg|
                result.concat(resolve_single_package_name(pkg))
            rescue PackageUnavailable => e
                if include_unavailable
                    result.concat([[:osdeps, pkg]])
                else
                    raise e, "cannot resolve #{pkg}: #{e}", e.backtrace
                end
            rescue PackageNotFound => e
                raise e, "cannot resolve #{pkg}: #{e}", e.backtrace
            end
            result
        end

        # @api private
        #
        # Resolves a package name, where +name+ cannot be resolved as a
        # metapackage
        #
        # This is a helper method for #resolve_package_name. Do not use
        # directly
        #
        # @return [nil,Array] either nil if there is no such osdep, or a list of
        #   (type, package_name) pairs where type is either :package or :osdeps and
        #   package_name the corresponding package name
        def resolve_single_package_name(name)
            resolve_package_name_as_osdep(name)
        rescue PackageNotFound => osdep_error
            begin
                resolve_package_name_as_source_package(name)
            rescue PackageNotFound
                raise osdep_error, "#{osdep_error} and it cannot be resolved as a source package"
            end
        end

        # @api private
        #
        # Resolve a package name that is assumed to be a source package
        #
        # @param [String] name the name to be resolved
        # @return [nil,Array] either nil if there is no such osdep, or a list of
        #   (type, package_name) pairs where type is either :package or :osdep and
        #   package_name the corresponding package name
        # @raise PackageNotFound if the given package name cannot be resolved
        #   into a package
        def resolve_package_name_as_source_package(name)
            unless (pkg = find_autobuild_package(name))
                raise PackageNotFound,
                      "cannot resolve #{name}: it is neither a package nor an osdep"
            end

            [[:package, pkg.name]]
        end

        # @api private
        #
        # Resolve a potential osdep name, either as the osdep itself, or as
        # source packages that are used as osdep override
        #
        # @return [nil,Array] either nil if there is no such osdep, or a list of
        #   (type, package_name) pairs where type is either :package or :osdep and
        #   package_name the corresponding package name
        # @raise PackageNotFound if the given package name cannot be resolved
        #   into a package. If {#accept_unavailable_osdeps?} is false (the
        #   default), the exception will be raised if the package is known to be
        #   an osdep, but it is not available on the local operating system (as
        #   defined by {#os_package_resolver}), and there has been no source
        #   fallback defined with {#add_osdeps_overrides}.
        #   If true, it will return it as an osdep.
        def resolve_package_name_as_osdep(name)
            osdeps_availability = os_package_resolver.availability_of(name)
            if osdeps_availability == OSPackageResolver::NO_PACKAGE
                raise PackageNotFound, "#{name} is not an osdep"
            end

            # There is an osdep definition for this package, check the
            # overrides
            osdeps_available =
                (osdeps_availability == OSPackageResolver::AVAILABLE) ||
                (osdeps_availability == OSPackageResolver::IGNORE)
            osdeps_overrides = self.osdeps_overrides[name]
            if osdeps_overrides && (!osdeps_available || osdeps_overrides[:force])
                osdeps_overrides[:packages].inject([]) do |result, src_pkg_name|
                    result.concat(resolve_package_name_as_source_package(src_pkg_name))
                end.uniq
            elsif !osdeps_available && (pkg = find_autobuild_package(name))
                [[:package, pkg.name]]
            elsif osdeps_available || accept_unavailable_osdeps?
                [[:osdeps, name]]
            elsif osdeps_availability == OSPackageResolver::WRONG_OS
                raise PackageUnavailable, "#{name} is an osdep, but it is not available for this operating system (#{os_package_resolver.operating_system})"
            elsif osdeps_availability == OSPackageResolver::UNKNOWN_OS
                raise PackageUnavailable, "#{name} is an osdep, but the local operating system is unavailable"
            elsif osdeps_availability == OSPackageResolver::NONEXISTENT
                raise PackageUnavailable, "#{name} is an osdep, but it is explicitely marked as 'nonexistent' for this operating system (#{os_package_resolver.operating_system})"
            end
        end

        def find_metapackage(name)
            @metapackages[name.to_s]
        end

        # Add packages to a metapackage, creating the metapackage if it does not
        # exist
        #
        # @overload metapackage(name)
        #   Create a metapackage
        #
        #   @return [Metapackage]
        #
        # @overload metapackage(name, *packages)
        #   Add packages to a new or existing metapackage
        #
        #   @param [String] name the name of the metapackage. If it already
        #     exists, the packages will be added to it.
        #   @param [String] packages list of package names to be added to the
        #     metapackage
        #   @return [Metapackage]
        #
        def metapackage(name, *packages, &block)
            meta = (@metapackages[name.to_s] ||= Metapackage.new(name))
            packages.each do |arg|
                if !arg.respond_to?(:to_str)
                    meta.add(arg)
                elsif (pkg = find_autobuild_package(arg))
                    meta.add(pkg)
                elsif (pkg_set = find_metapackage(arg))
                    pkg_set.each_package do |pkg_in_set|
                        meta.add(pkg_in_set)
                    end
                elsif os_package_resolver.has?(arg)
                    raise ArgumentError, "cannot specify the osdep #{arg} as an element of a metapackage"
                else
                    raise PackageNotFound, "cannot find a package called #{arg}"
                end
            end

            meta.instance_eval(&block) if block
            meta
        end

        # Lists all defined metapackages
        #
        # Autoproj defines one metapackage per package set, which by default
        # includes all the packages that the package set defines.
        def each_metapackage(&block)
            metapackages.each_value(&block)
        end

        # Returns the packages selected in this manifest's layout
        #
        # @return [PackageSelection]
        def layout_packages(validate = true)
            result = PackageSelection.new
            Autoproj.in_file(file) do
                normalized_layout.each_key do |pkg_or_set|
                    weak =
                        if (meta = metapackages[pkg_or_set])
                            meta.weak_dependencies?
                        end

                    resolve_package_name(pkg_or_set).each do |pkg_type, pkg_name|
                        result.select(
                            pkg_or_set, pkg_name,
                            osdep: (pkg_type == :osdeps),
                            weak: weak
                        )
                    end
                rescue PackageNotFound => e
                    raise e, "#{pkg_or_set}, which is selected in the layout, "\
                             "is unknown: #{e.message}", e.backtrace
                end
            end

            begin
                result.filter_excluded_and_ignored_packages(self)
            rescue ExcludedSelection => e
                if validate
                    raise e, "#{e.selection}, which is selected in the layout, cannot be built: #{e.message}", e.backtrace
                end
            end
            result
        end

        # Returns the set of package names that are explicitely listed in the
        # layout, minus the excluded and ignored ones
        def all_layout_packages(validate = true)
            default_packages(validate)
        end

        # Returns all defined package names
        def all_package_names
            each_autobuild_package.map(&:name)
        end

        # Returns true if +name+ is a valid package and is included in the build
        #
        # If +validate+ is true, the method will raise ArgumentError if the
        # package does not exists.
        #
        # If it is false, the method will simply return false on non-defined
        # packages
        def package_enabled?(name, validate = true)
            Autoproj.warn_deprecated "#package_enabled? and #package_selected? were broken in autoproj v1, and there are usually other ways to get the same effect (as e.g. splitting package sets). Feel free to contact the autoproj developers if you have a use case that demands this functionality. For now, this method returns true for backward compatibility reasons."
            true
        end

        # Returns true if +name+ is a valid package and is neither excluded from
        # the build, nor ignored from the build
        #
        # If +validate+ is true, the method will raise ArgumentError if the
        # package does not exists.
        #
        # If it is false, the method will simply return false on non-defined
        # packages
        def package_selected?(name, validate = true)
            Autoproj.warn_deprecated "#package_enabled? and #package_selected? were broken in autoproj v1, and there are usually other ways to get the same effect (as e.g. splitting package sets). Feel free to contact the autoproj developers if you have a use case that demands this functionality. For now, this method returns true for backward compatibility reasons."
            true
        end

        # Returns the set of source packages that are selected by the layout
        #
        # @return [Array<PackageDefinition>]
        def all_selected_source_packages(validate = true)
            default_packages(validate).all_selected_source_packages(self)
        end

        # Returns the set of osdep packages that are selected by the layout
        #
        # @return [Array<String>]
        def all_selected_osdep_packages(validate = true)
            default_packages(validate).all_selected_osdep_packages(self)
        end

        # Returns the set of packages that are selected by the layout
        #
        # Unless {#default_packages}, it returns both the selected packages and
        # the dependencies (resolved recursively)
        #
        # @return [Array<String>] a list of source and osdep package names
        def all_selected_packages(validate = true)
            result = Set.new
            selection = default_packages(validate)

            root_sources = selection.each_source_package_name.to_set
            root_sources.each do |pkg_name|
                find_autobuild_package(pkg_name).all_dependencies_with_osdeps(result)
            end
            result | root_sources | selection.each_osdep_package_name.to_set
        end

        # Returns the set of packages that should be built if the user does not
        # specify any on the command line
        def default_packages(validate = true)
            if has_layout?
                layout_packages(validate)
            else
                result = PackageSelection.new
                all_package_names.each do |pkg_name|
                    package_type, package_name = resolve_single_package_name(pkg_name).first
                    next if excluded?(package_name) || ignored?(package_name)

                    result.select(package_name, package_name, osdep: (package_type == :osdeps))
                end
                result
            end
        end

        # @api private
        #
        # Compute a layout structure that is normalized
        def compute_normalized_layout(result, layout_level, layout_data)
            layout_data.each do |value|
                if value.kind_of?(Hash)
                    subname, subdef = value.find { true }
                    if subdef
                        compute_normalized_layout(result, "#{layout_level}#{subname}/", subdef)
                    end
                else
                    result[value] = layout_level
                end
            end
            result
        end

        # Returns the level of the layout into which of a certain package
        # would be selected
        #
        # @return [String]
        def whereis(package_name)
            package_name = validate_package_name_argument(package_name)

            matches = [package_name]
            if (source_package = find_package_definition(package_name))
                each_metapackage do |meta|
                    matches << meta.name if meta.include?(source_package)
                end
            end

            matches.each do |name|
                if (place = normalized_layout[name])
                    return place
                end
            end
            "/"
        end

        class NoPackageXML < ConfigError; end

        # Loads the package's manifest.xml file for the current package
        #
        # Right now, the absence of a manifest makes autoproj only issue a
        # warning. This will later be changed into an error.
        def load_package_manifest(pkg)
            if pkg.respond_to?(:to_str)
                pkg_definition = find_package_definition(pkg)
                unless pkg_definition
                    raise ArgumentError, "#{pkg} is not a known package in #{self}"
                end

                pkg = pkg_definition
            end
            package = pkg.autobuild
            package_set = pkg.package_set

            # Look for the package's manifest.xml, but fallback to a manifest in
            # the package set if present
            if package.use_package_xml? && package.checked_out?
                manifest_path = File.join(package.srcdir, "package.xml")
                raise NoPackageXML.new(package.srcdir), "#{package.name} from "\
                                                        "#{package_set.name} has use_package_xml set, but the package has "\
                                                        "no package.xml file" unless File.file?(manifest_path)

                manifest = PackageManifest.load(package, manifest_path,
                                                ros_manifest: true,
                                                condition_context: @ws.env)
            else
                manifest_paths = [File.join(package.srcdir, "manifest.xml")]
                if package_set.local_dir
                    manifest_paths << File.join(
                        package_set.local_dir, "manifests", "#{package.name}.xml"
                    )
                end
                manifest_path = manifest_paths.find do |path|
                    File.file?(path)
                end
                if manifest_path
                    manifest = PackageManifest.load(package, manifest_path,
                                                    ros_manifest: false,
                                                    condition_context: @ws.config)
                end
            end

            if manifest
                pkg.autobuild.description = manifest
            else
                Autoproj.warn "#{package.name} from #{package_set.name} "\
                              "does not have a manifest"
            end

            pkg.apply_dependencies_from_manifest
            # #description is initialized with a null package manifest
            # return it even if we haven't overriden it
            pkg.autobuild.description
        end

        def load_all_available_package_manifests
            # Load the manifest for packages that are already present on the
            # file system
            each_package_definition do |pkg|
                if pkg.checked_out?
                    begin
                        load_package_manifest(pkg)
                    rescue Interrupt
                        raise
                    rescue Exception => e
                        Autoproj.warn "cannot load package manifest for #{pkg.name}: #{e.message}"
                    end
                end
            end
        end

        # The set of overrides added with #add_osdeps_overrides
        attr_reader :osdeps_overrides

        # Declares that autoproj should use normal package(s) to provide the
        # +osdeps_name+ OS package in cases +osdeps_name+ does not exist.
        #
        # The full syntax is
        #
        #   Autoproj.add_osdeps_overrides 'opencv', :package => 'external/opencv'
        #
        # If more than one packages should be built, use the :packages option
        # with an array:
        #
        #   Autoproj.add_osdeps_overrides 'opencv', :packages => ['external/opencv', 'external/test']
        #
        # The :force option allows to force the usage of the source package(s),
        # regardless of the availability of the osdeps package.
        def add_osdeps_overrides(osdeps_name, package: osdeps_name, packages: [], force: false)
            packages << package if package
            packages.each { |pkg_name| resolve_package_name(pkg_name) }
            @osdeps_overrides[osdeps_name.to_s] = Hash[packages: packages, force: force]
        end

        # Remove any OSDeps override that has previously been added with
        # #add_osdeps_overrides
        def remove_osdeps_overrides(osdeps_name)
            @osdeps_overrides.delete(osdeps_name.to_s)
        end

        PackageSelection = Autoproj::PackageSelection

        # @api private
        #
        # Helper for {#expand_package_selection}
        def update_selection(selection, user_selection_string, name, weak)
            source_packages = Array.new
            osdeps = Array.new
            resolve_package_name(name).each do |type, resolved_name|
                if type == :package
                    source_packages << resolved_name
                else
                    osdeps << resolved_name
                end
            end
            unless source_packages.empty?
                selection.select(user_selection_string, source_packages, osdep: false, weak: weak)
            end
            unless osdeps.empty?
                selection.select(user_selection_string, osdeps, osdep: true, weak: weak)
            end
        end

        # Normalizes package selection strings into a PackageSelection object
        #
        # @param [Array<String>] selection the package selection strings. For
        #   source packages, it can either be the package name, a package set
        #   name, or a prefix of the package's source directory. For osdeps, it
        #   has to be the plain package name
        # @return [PackageSelection, Array<String>]
        def expand_package_selection(selection, filter: true)
            result = PackageSelection.new

            all_selected_packages = self.all_selected_packages.to_set
            all_source_package_names = all_package_names
            all_osdeps_package_names = os_package_resolver.all_package_names
            selection.each do |sel|
                match_pkg_name = Regexp.new(Regexp.quote(sel))
                all_matches = Array.new
                each_metapackage do |meta_pkg|
                    if meta_pkg.name =~ match_pkg_name
                        all_matches << [meta_pkg.name, meta_pkg.name == sel]
                    end
                end
                all_source_package_names.each do |pkg_name|
                    pkg = find_autobuild_package(pkg_name)
                    if pkg.name =~ match_pkg_name
                        all_matches << [pkg.name, pkg.name == sel]
                    elsif "#{sel}/".start_with?("#{pkg.srcdir}/")
                        all_matches << [pkg.name, true]
                    elsif pkg.respond_to?(:builddir) && "#{sel}/".start_with?("#{pkg.builddir}/")
                        all_matches << [pkg.name, true]
                    elsif pkg.srcdir.start_with?(sel) && all_selected_packages.include?(pkg.name)
                        all_matches << [pkg.name, false]
                    end
                end
                all_osdeps_package_names.each do |pkg_name|
                    if pkg_name =~ match_pkg_name
                        all_matches << [pkg_name, pkg_name == sel]
                    end
                end

                exact_matches, partial_matches =
                    all_matches.partition { |_, exact_match| exact_match }
                selected_partial_matches, not_selected_partial_matches =
                    partial_matches.partition { |pkg_name, _| all_selected_packages.include?(pkg_name) }
                not_selected_partial_matches.clear if result.has_match_for?(sel)

                matches =
                    [exact_matches, selected_partial_matches, not_selected_partial_matches]
                    .find { |m| !m.empty? }

                matches&.each do |pkg_name, _|
                    update_selection(result, sel, pkg_name, true)
                end
            end

            result.filter_excluded_and_ignored_packages(self) if filter

            nonresolved = selection - result.matches.keys
            [result, nonresolved]
        end

        attr_reader :moved_packages

        # Moves the given package name from its current subdirectory to the
        # provided one.
        #
        # For instance, for a package called drivers/xsens_imu
        #
        #   move("drivers/xsens_imu", "data_acquisition")
        #
        # will move the package into data_acquisition/xsens_imu
        def move_package(package_name, new_dir)
            moved_packages[package_name] = File.join(new_dir, File.basename(package_name))
        end

        # Compute the reverse dependencies of all the packages
        #
        # The return value is a hash of the form
        #
        #   package_name => [list_of_packages_that_depend_on_package_name]
        #
        # Where the list is given as a list of package names as well
        def compute_revdeps
            result = Hash.new { |h, k| h[k] = Set.new }
            each_autobuild_package do |pkg|
                pkg.dependencies.each do |pkg_name|
                    result[pkg_name] << pkg.name
                end
                pkg.optional_dependencies.each do |pkg_name|
                    result[pkg_name] << pkg.name
                end
                pkg.os_packages.each do |pkg_name|
                    result[pkg_name] << pkg.name
                end
            end
            result
        end

        # Declare that we should reuse the autoproj installation present at the
        # given path
        def reuse(workspace_root)
            return if reused_installations.any? { |mnf| mnf.path == workspace_root }

            manifest = InstallationManifest.from_workspace_root(workspace_root)
            manifest.load
            @reused_installations << manifest
            manifest.each do |pkg|
                ignore_package pkg.name
            end
        end
    end

    def self.manifest
        Autoproj.warn_deprecated(
            __method__, "use workspace.manifest instead"
        )

        workspace.manifest
    end

    def self.osdeps
        Autoproj.warn_deprecated(
            __method__, "use workspace.os_package_resolver or workspace.os_package_installer instead"
        )

        workspace.os_package_resolver
    end

    def self.config
        workspace.config
    end

    def self.add_osdeps_overrides(*args, **kw, &block)
        manifest.add_osdeps_overrides(*args, **kw, &block)
    end
end
