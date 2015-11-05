require 'yaml'
require 'csv'
require 'utilrb/kernel/options'
require 'set'
require 'rexml/document'

require 'win32/dir' if RbConfig::CONFIG["host_os"] =~%r!(msdos|mswin|djgpp|mingw|[Ww]indows)! 

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

        # Load the manifest data contained in +file+
        def load(file)
            if !File.exists?(file)
                raise ConfigError.new(File.dirname(file)), "expected an autoproj configuration in #{File.dirname(file)}, but #{file} does not exist"
            end

            data = Autoproj.in_file(file, Autoproj::YAML_LOAD_ERROR) do
                YAML.load(File.read(file))
            end

            @file = file
            @data = data
            @ignored_packages |= (data['ignored_packages'] || Set.new).to_set
            @manifest_exclusions |= (data['exclude_packages'] || Set.new).to_set

            @normalized_layout = Hash.new
            compute_normalized_layout(
                normalized_layout,
                '/',
                data['layout'] || Hash.new)

            if data['constants']
                @constant_definitions = Autoproj.resolve_constant_definitions(data['constants'])
            end
        end

        # The manifest data as a Hash
        attr_reader :data

        # The set of packages defined so far as a mapping from package name to 
        # [Autobuild::Package, package_set, file] tuple
        attr_reader :packages

        # A mapping from package names into PackageManifest objects
        attr_reader :package_manifests

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
        def accept_unavailable_osdeps?; !!@accept_unavailable_osdeps end

        # Sets {#accept_unavailable_osdeps?}
        def accept_unavailable_osdeps=(flag); @accept_unavailable_osdeps = flag end

        # True if osdeps should be handled in update and build, or left to the
        # osdeps command
        def auto_osdeps?
            if data.has_key?('auto_osdeps')
                !!data['auto_osdeps']
            else true
            end
        end

        attr_reader :constant_definitions

        attr_reader :metapackages

        # The VCS object for the main configuration itself
        attr_accessor :vcs

        # The definition of all OS packages available on this installation
        attr_reader :os_package_resolver

	def initialize
            @file = nil
	    @data = Hash.new
            @packages = Hash.new
            @package_manifests = Hash.new
            @package_sets = []
            @os_package_resolver = OSPackageResolver.new

            @automatic_exclusions = Hash.new
            @constants_definitions = Hash.new
            @disabled_imports = Set.new
            @moved_packages = Hash.new
            @osdeps_overrides = Hash.new
            @metapackages = Hash.new
            @ignored_os_packages = Set.new
            @reused_installations = Array.new
            @ignored_packages = Set.new
            @manifest_exclusions = Set.new
            @accept_unavailable_osdeps = false

            @constant_definitions = Hash.new
            @package_sets << LocalPackageSet.new(self)
	end


        # Call this method to ignore a specific package. It must not be used in
        # init.rb, as the manifest is not yet loaded then
        def ignore_package(package_name)
            @ignored_packages << package_name.to_str
        end

        # True if the given package should not be built, with the packages that
        # depend on him have this dependency met.
        #
        # This is useful if the packages are already installed on this system.
        def ignored?(package_name)
            ignored_packages.any? do |l|
                if package_name == l
                    true
                elsif (pkg_set = metapackages[l]) && pkg_set.include?(package_name)
                    true
                else
                    false
                end
            end
        end

        # Enumerates the package names of all ignored packages
        def each_excluded_package
            each_autobuild_package do |pkg|
                yield(pkg) if excluded?(pkg.name)
            end
        end

        # Enumerates the package names of all ignored packages
        def each_ignored_package
            each_autobuild_package do |pkg|
                yield(pkg) if ignored?(pkg.name)
            end
        end

        # Removes all registered exclusions
        def clear_exclusions
            automatic_exclusions.clear
            data['exclude_packages'].clear
        end

        # Removes all registered ignored packages
        def clear_ignored
            ignored_packages.clear
        end

        # The set of package names that are listed in the excluded_packages
        # section of the manifest
        def manifest_exclusions
            @manifest_exclusions
        end

        # A package_name => reason map of the exclusions added with #add_exclusion.
        # Exclusions listed in the manifest file are returned by #manifest_exclusions
        attr_reader :automatic_exclusions

        # Exclude +package_name+ from the build. +reason+ is a string describing
        # why the package is to be excluded.
        def add_exclusion(package_name, reason)
            automatic_exclusions[package_name] = reason
        end

        # Tests whether the given package is excluded in the manifest
        def excluded_in_manifest?(package_name)
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
            if excluded_in_manifest?(package_name)
                "#{package_name} is listed in the exclude_packages section of the manifest"
            else
                automatic_exclusions[package_name]
            end
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

        # True if the given package should not be built and its dependencies
        # should be considered as met.
        #
        # This is useful to avoid building packages that are of no use for the
        # user.
        def excluded?(package_name)
            package_name = package_name.to_str

            if excluded_in_manifest?(package_name)
                true
            elsif automatic_exclusions.any? { |pkg_name, | pkg_name == package_name }
                true
            else
                false
            end
        end

        # Lists the autobuild files that are in the package sets we know of
	def each_autobuild_file(source_name = nil, &block)
            if !block_given?
                return enum_for(__method__, source_name)
            end

            # This looks very inefficient, but it is because source names are
            # contained in source.yml and we must therefore load that file to
            # check the package set name ...
            #
            # And honestly I don't think someone will have 20 000 package sets
            done_something = false
            each_package_set do |source| 
                next if source_name && source.name != source_name
                done_something = true

                Dir.glob(File.join(source.local_dir, "*.autobuild")).sort.each do |file|
                    yield(source, file)
                end
            end

            if source_name && !done_something
                raise ConfigError.new(file), "in #{file}: package set '#{source_name}' does not exist"
            end
	end

        # Yields each osdeps definition files that are present in our sources
        def each_osdeps_file
            if !block_given?
                return enum_for(__method__)
            end

            each_package_set do |source|
		Dir.glob(File.join(source.local_dir, "*.osdeps")).each do |file|
		    yield(source, file)
		end
            end
        end

        # True if some of the sources are remote sources
        def has_remote_sources?
            each_remote_source(false).any? { true }
        end

        # Like #each_package_set, but filters out local package sets
        def each_remote_package_set
            return enum_for(__method__) if !block_given?

            each_package_set do |pkg_set|
                if !pkg_set.local?
                    yield(pkg_set)
                end
            end
        end

        # Enumerates the version control information for all the package sets
        # listed directly in the manifest file
        #
        # @yieldparam [VCSDefinition] vcs the package set VCS object
        # @yieldparam [Hash] options additional import options
        # @options options [Boolean] :auto_update (true) if true, the set of
        #   package sets declared as imports in package set's source.yml file
        #   will be auto-imported by autoproj, otherwise they won't
        # @return [nil]
        def each_raw_explicit_package_set
            return enum_for(__method__) if !block_given?
            (data['package_sets'] || []).map do |spec|
                Autoproj.in_file(self.file) do
                    yield(*PackageSet.resolve_definition(self, spec))
                end
            end
            nil
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

        # Load the package set information
        def load_and_update_package_sets
            Autoproj.warn_deprecated __method__,
                "use Ops::Configuration instead"
            Ops::Configuration.new(Autoproj.workspace).load_and_update_package_sets
        end

        # Returns a package set that is used by autoproj for its own purposes
        def local_package_set
            each_package_set.find { |s| s.kind_of?(LocalPackageSet) }
        end

        # Registers a new package set
        def register_package_set(pkg_set)
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
            pkg = PackageDefinition.new(package, package_set, file)
            if block
                pkg.add_setup_block(block)
            end
            @packages[package.name] = pkg
            metapackage pkg.package_set.name, pkg.autobuild
            metapackage "#{pkg.package_set.name}.all", pkg.autobuild
            pkg
        end

        # Returns the package set that defines a package
        #
        # @param [String] package_name the package name
        # @return [PackageSet] the package set
        # @raise ArgumentError if package_name is not the name of a known
        #   package
        def definition_package_set(package_name)
            if pkg_def = @packages[package_name]
                pkg_def.package_set
            else raise ArgumentError, "no package called #{package_name}"
            end
        end

        # @deprecated use {definition_package_set} instead
        def definition_source(package_name)
            definition_package_set(package_name)
        end

        # Returns the full path to the file that defines a package
        #
        # @param [String] package_name the package name
        # @return [String] the package set
        # @raise ArgumentError if package_name is not the name of a known
        #   package
        def definition_file(package_name)
            if pkg_def = @packages[package_name]
                pkg_def.file
            else raise ArgumentError, "no package called #{package_name}"
            end
        end

        def find_package(name)
            if name.respond_to?(:name)
                name = name.name
            end

            packages[name.to_str]
        end

        def find_autobuild_package(name)
            if name.respond_to?(:name)
                name = name.name
            end

            if pkg = packages[name.to_str]
                pkg.autobuild
            end
        end

        def package(name)
            find_package(name)
        end

        # @deprecated use {each_autobuild_package} instead
        def each_package(&block)
            Autoproj.warn "Manifest#each_package is deprecated, use each_autobuild_package instead"
            Autoproj.warn "  " + caller.join("\n  ")
            each_autobuild_package(&block)
        end

        # Lists all defined packages
        #
        # @yieldparam [PackageDefinition] pkg
        def each_package_definition(&block)
            if !block_given?
                return enum_for(:each_package_definition)
            end
            packages.each_value(&block)
        end

        # Lists the autobuild objects for all defined packages
        #
        # @yieldparam [Autobuild::Package] pkg
        def each_autobuild_package
            return enum_for(__method__) if !block_given?
            packages.each_value { |pkg| yield(pkg.autobuild) }
        end

        # @deprecated use Ops::Tools.create_autobuild_package or include
        #   Ops::Tools into your class to get it as instance method
        def self.create_autobuild_package(vcs, text_name, into)
            Autoproj.warn_deprecated __method__, "use Ops::Tools.create_autobuild_package instead"
            Ops::Tools.create_autobuild_package(vcs, text_name, into)
        end

        # @deprecated use Ops::Configuration#update_main_configuration
        def update_yourself(only_local = false)
            Autoproj.warn_deprecated __method__, "use Ops::Configuration instead"
            Ops::Configuration.new(Autoproj.workspace).update_main_configuration(only_local)
        end

        # @deprecated use Ops::Configuration.update_remote_package_set
        def update_remote_set(vcs, only_local = false)
            Autoproj.warn_deprecated __method__, "use Ops::Configuration instead"
            Ops::Configuration.update_remote_package_set(vcs, only_local)
        end

        # Compute the VCS definition for a given package
        #
        # @param [String] package_name the name of the package to be resolved
        # @param [PackageSet,nil] package_source the package set that defines the
        #   given package, defaults to the package's definition source (as
        #   returned by {definition_package_set}) if not given
        # @return [VCSDefinition] the VCS definition object
        def importer_definition_for(package_name, package_set = definition_package_set(package_name),
                                    options = Hash.new)
            options = validate_options options, mainline: nil
            mainline = 
                if options[:mainline] == true
                    package_set
                else
                    options[:mainline]
                end

            vcs = package_set.importer_definition_for(package_name)
            return if !vcs

            # Get the sets that come *after* the one that defines the package to
            # apply the overrides
            package_sets = each_package_set.to_a.dup
            while !package_sets.empty? && package_sets.first != package_set
                set = package_sets.shift
                return vcs if set == mainline
            end
            set = package_sets.shift
            return vcs if set == mainline

            # Then apply the overrides
            package_sets.inject(vcs) do |updated_vcs, pkg_set|
                updated_vcs = pkg_set.overrides_for(package_name, updated_vcs)
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
        def load_importers(options = Hash.new)
            packages.each_value do |pkg|
                vcs = importer_definition_for(pkg.autobuild.name, pkg.package_set, options) ||
                    pkg.package_set.default_importer


                if vcs
                    pkg.vcs = vcs
                    pkg.autobuild.importer = vcs.create_autobuild_importer
                else
                    raise ConfigError.new, "source #{pkg.package_set.name} defines #{pkg.autobuild.name}, but does not provide a version control definition for it"
                end
            end
        end

        # Checks if there is a package with a given name
        #
        # @param [String] name
        # @return [Boolean]
        def has_package?(name)
            packages.has_key?(name)
        end

        # Returns true if +name+ is the name of a package set known to this
        # autoproj installation
        def has_package_set?(name)
            each_package_set.find { |set| set.name == name }
        end

        # Returns the PackageSet object for the given package set, or raises
        # ArgumentError if none exists with that name
        def package_set(name)
            set = each_package_set.find { |set| set.name == name }
            if !set
                raise ArgumentError, "no package set called #{name} exists"
            end
            set
        end

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
        #   (type, package_name) pairs where type is either :package or :osdep and
        #   package_name the corresponding package name
        # @raise [PackageNotFound] if the given package name cannot be resolved
        #   into a package. If {#accept_unavailable_osdeps?} is false (the
        #   default), the exception will be raised if the package is known to be
        #   an osdep, but it is not available on the local operating system (as
        #   defined by {#os_package_resolver}), and there has been no source
        #   fallback defined with {#add_osdeps_overrides}. If true, it will
        #   return such a package as an osdep.
        def resolve_package_name(name)
            if pkg_set = find_metapackage(name)
                pkg_names = pkg_set.each_package.map(&:name)
            else
                pkg_names = [name.to_str]
            end

            result = []
            pkg_names.each do |pkg|
                begin
                    result.concat(resolve_single_package_name(pkg))
                rescue PackageNotFound => e
                    raise PackageNotFound, "cannot resolve #{pkg}: #{e}", e.backtrace
                end
            end
            result
        end

        # Resolves all the source package dependencies for given packages
        #
        # @param [Set<String>] the set of package names of which we want to
        #   discover the dependencies
        # @return [Set<String>] the set of all package names that the packages designed
        #   by root_names depend on
        def resolve_packages_dependencies(*root_names)
            result = Set.new
            queue = root_names.dup
            while pkg_name = queue.shift
                next if result.include?(pkg_name)
                result << pkg_name

                pkg = find_autobuild_package(pkg_name)
                pkg.dependencies.each do |dep_name|
                    queue << dep_name
                end
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
        #   (type, package_name) pairs where type is either :package or :osdep and
        #   package_name the corresponding package name
        def resolve_single_package_name(name)
            resolve_package_name_as_osdep(name)
        rescue PackageNotFound => osdep_error
            begin
                resolve_package_name_as_source_package(name)
            rescue PackageNotFound
                raise PackageNotFound, "#{osdep_error} and it cannot be resolved as a source package"
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
            if pkg = find_autobuild_package(name)
                return [[:package, pkg.name]]
            else
                raise PackageNotFound, "cannot resolve #{name}: it is neither a package nor an osdep"
            end
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
                source_packages = osdeps_overrides[:packages].inject([]) do |result, src_pkg_name|
                    result.concat(resolve_package_name_as_source_package(src_pkg_name))
                end.uniq
            elsif !osdeps_available && (pkg = find_autobuild_package(name))
                return [[:package, pkg.name]]
            elsif osdeps_available || accept_unavailable_osdeps?
                return [[:osdeps, name]]
            elsif osdeps_availability == OSPackageResolver::WRONG_OS
                raise PackageNotFound, "#{name} is an osdep, but it is not available for this operating system"
            elsif osdeps_availability == OSPackageResolver::UNKNOWN_OS
                raise PackageNotFound, "#{name} is an osdep, but the local operating system is unavailable"
            elsif osdeps_availability == OSPackageResolver::NONEXISTENT
                raise PackageNotFound, "#{name} is an osdep, but it is explicitely marked as 'nonexistent' for this operating system"
            end
        end

        # +name+ can either be the name of a source or the name of a package. In
        # the first case, we return all packages defined by that source. In the
        # latter case, we return the singleton array [name]
        def resolve_package_set(name)
            if find_autobuild_package(name)
                [name]
            else
                pkg_set = find_metapackage(name)
                if !pkg_set
                    raise UnknownPackage.new(name), "#{name} is neither a package nor a package set name. Packages in autoproj must be declared in an autobuild file."
                end
                pkg_set.each_package.
                    map(&:name).
                    find_all { |pkg_name| !os_package_resolver.has?(pkg_name) }
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
            packages.each do |pkg|
                if pkg.respond_to?(:to_str)
                    package_names = resolve_package_set(pkg)
                    package_names.each do |pkg_name|
                        meta.add(find_autobuild_package(pkg_name))
                    end
                else
                    meta.add(pkg)
                end
            end

            if block
                meta.instance_eval(&block)
            end
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
        def layout_packages(validate)
            result = PackageSelection.new
            Autoproj.in_file(self.file) do
                normalized_layout.each_key do |pkg_or_set|
                    begin
                        weak = if meta = metapackages[pkg_or_set]
                                   meta.weak_dependencies?
                               end


                        result.select(pkg_or_set, resolve_package_set(pkg_or_set), weak: weak)
                    rescue UnknownPackage => e
                        raise e, "#{e.name}, which is selected in the layout, is unknown: #{e.message}", e.backtrace
                    end
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

        # Enumerates the sublayouts defined in +layout_def+.
        def each_sublayout(layout_def)
            layout_def.each do |value|
                if value.kind_of?(Hash)
                    name, layout = value.find { true }
                    yield(name, layout)
                end
            end
        end

        # Returns the set of package names that are explicitely listed in the
        # layout, minus the excluded and ignored ones
        def all_layout_packages(validate = true)
            default_packages(validate)
        end

        # Returns all defined package names, minus the excluded and ignored ones
        def all_package_names
            each_autobuild_package.map(&:name)
        end

        # Returns all the packages that can be built in this installation
        def all_packages
            result = Set.new
            each_package_set do |pkg_set|
                result |= metapackage(pkg_set.name).packages.map(&:name).to_set
            end
            result.to_a.
                find_all { |pkg_name| !os_package_resolver.has?(pkg_name) }
        end

        # Returns true if +name+ is a valid package and is included in the build
        #
        # If +validate+ is true, the method will raise ArgumentError if the
        # package does not exists. 
        #
        # If it is false, the method will simply return false on non-defined
        # packages 
        def package_enabled?(name, validate = true)
            if !find_autobuild_package(name) && !os_package_resolver.has?(name)
                if validate
                    raise ArgumentError, "package #{name} does not exist"
                end
                return false
            end

            !excluded?(name)
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
            if package_enabled?(name)
                !ignored?(name)
            end
        end

        # Returns the set of packages that are selected by the layout
        def all_selected_packages(validate = true)
            result = Set.new
            root = default_packages(validate).source_packages.to_set
            root.each do |pkg_name|
                find_autobuild_package(pkg_name).all_dependencies(result)
            end
            result | root
        end

        # Returns the set of packages that should be built if the user does not
        # specify any on the command line
        def default_packages(validate = true)
            if layout = data['layout']
                return layout_packages(validate)
            else
                result = PackageSelection.new
                # No layout, all packages are selected
                names = all_packages
                names.delete_if { |pkg_name| excluded?(pkg_name) || ignored?(pkg_name) }
                names.each do |pkg_name|
                    result.select(pkg_name, pkg_name)
                end
                result
            end
        end

        # A mapping from names to layout placement, as found in the layout
        # section of the manifest
        attr_reader :normalized_layout

        def compute_normalized_layout(result, layout_level, layout_data)
            layout_data.each do |value|
                if value.kind_of?(Hash)
                    subname, subdef = value.find { true }
                    if subdef
                        normalized_layout(result, "#{layout_level}#{subname}/", subdef)
                    end
                else
                    result[value] = layout_level
                end
            end
            result
        end

        # Returns the package directory for the given package name
        def whereis(package_name)
            Autoproj.in_file(self.file) do
                set_name = definition_package_set(package_name).name
                actual_layout = normalized_layout
                return actual_layout[package_name] || actual_layout[set_name] || '/'
            end
        end

        def resolve_optional_dependencies
            packages.each_value do |pkg|
                pkg.autobuild.resolve_optional_dependencies
            end
        end

        # Loads the package's manifest.xml file for the current package
        #
        # Right now, the absence of a manifest makes autoproj only issue a
        # warning. This will later be changed into an error.
        def load_package_manifest(pkg)
            if pkg.respond_to?(:to_str)
                pkg = packages.values.
                    find { |p| p.autobuild.name == pkg }
            end
            package, package_set, file = pkg.autobuild, pkg.package_set, pkg.file

            if !pkg
                raise ArgumentError, "package #{pkg} is not defined"
            end

            manifest_paths =
                [File.join(package_set.local_dir, "manifests", package.name + ".xml"), File.join(package.srcdir, "manifest.xml")]
            manifest_path = manifest_paths.find do |path|
                File.directory?(File.dirname(path)) &&
                    File.file?(path)
            end

            manifest =
                if !manifest_path
                    if !pkg.autobuild.description
                        Autoproj.warn "#{package.name} from #{package_set.name} does not have a manifest"
                        PackageManifest.new(package)
                    else
                        pkg.autobuild.description
                    end
                else
                    PackageManifest.load(package, manifest_path)
                end

            pkg.autobuild.description = manifest
            package_manifests[package.name] = manifest

            manifest.each_dependency(pkg.modes) do |name, is_optional|
                begin
                    if is_optional
                        package.optional_dependency name
                    else
                        package.depends_on name
                    end
                rescue Autobuild::ConfigException => e
                    raise ConfigError.new(manifest_path),
                        "manifest #{manifest_path} of #{package.name} from #{package_set.name} lists '#{name}' as dependency, which is listed in the layout of #{file} but has no autobuild definition", e.backtrace
                rescue ConfigError => e
                    raise ConfigError.new(manifest_path),
                        "manifest #{manifest_path} of #{package.name} from #{package_set.name} lists '#{name}' as dependency, but it is neither a normal package nor an osdeps package. osdeps reports: #{e.message}", e.backtrace
                end
            end
            manifest
        end

        # Loads the manifests for all packages known to this project.
        #
        # See #load_package_manifest
        def load_package_manifests(selected_packages)
            selected_packages.each(&:load_package_manifest)
        end

        # Disable all automatic imports from the given package set name
        def disable_imports_from(pkg_set_name)
            @disabled_imports << pkg_set_name
        end

        # call-seq:
        #   list_os_packages(packages) => required_packages, ospkg_to_pkg
        #
        # Returns the set of dependencies required by the listed packages.
        #
        # +required_packages+ is the set of osdeps names that are required for
        # +packages+ and +ospkg_to_pkg+ a mapping from the osdeps name to the
        # set of packages that require this OS package.
        def list_os_packages(packages)
            required_os_packages = Set.new
            package_os_deps = Hash.new { |h, k| h[k] = Array.new }
            packages.each do |pkg_name|
                pkg = find_autobuild_package(pkg_name)
                if !pkg
                    raise InternalError, "internal error: #{pkg_name} is not a package"
                end

                pkg.os_packages.each do |osdep_name|
                    package_os_deps[osdep_name] << pkg_name
                    required_os_packages << osdep_name
                end
            end

            return required_os_packages, package_os_deps
        end

        def filter_os_packages(required_os_packages, package_os_deps)
            required_os_packages.find_all do |pkg|
                if excluded?(pkg)
                    raise ConfigError.new, "the osdeps package #{pkg} is excluded from the build in #{file}. It is required by #{package_os_deps[pkg].join(", ")}"
                end
                if ignored?(pkg)
                    if Autoproj.verbose
                        Autoproj.message "ignoring osdeps package #{pkg}"
                    end
                    false
                else true
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
            if package
                packages << package
            end
            packages.each { |pkg_name| resolve_package_name(pkg_name) }
            @osdeps_overrides[osdeps_name.to_s] = Hash[packages: packages, force: force]
        end

        # Remove any OSDeps override that has previously been added with
        # #add_osdeps_overrides
        def remove_osdeps_overrides(osdep_name)
            @osdeps_overrides.delete(osdeps_name.to_s)
        end

        PackageSelection = Autoproj::PackageSelection

        # @api private
        #
        # Helper for {#expand_package_selection}
        def update_selection(selection, user_selection_string, name, weak)
            source_packages, osdeps = Array.new, Array.new
            resolve_package_name(name).each do |type, resolved_name|
                if type == :package
                    source_packages << resolved_name
                else
                    osdeps << resolved_name
                end
            end
            if !source_packages.empty?
                selection.select(user_selection_string, source_packages, osdep: false, weak: weak)
            end
            if !osdeps.empty?
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
        def expand_package_selection(selection, options = Hash.new)
            options = Kernel.validate_options options, filter: true
            result = PackageSelection.new

            # First, remove packages that are directly referenced by name or by
            # package set names. When it comes to packages (NOT package sets),
            # we prefer the ones selected in the layout
            all_selected_packages = self.all_selected_packages
            candidates = all_selected_packages.to_a +
                each_metapackage.map { |metapkg| [metapkg.name, metapkg.weak_dependencies?] }
            selection.each do |sel|
                match_pkg_name = Regexp.new(Regexp.quote(sel))
                candidates.each do |name, weak|
                    next if name !~ match_pkg_name
                    update_selection(result, sel, name, true)
                end
            end

            pending_selections = Hash.new { |h, k| h[k] = Array.new }

            # Finally, check for partial matches
            all_source_package_names = self.all_package_names
            all_osdeps_package_names = os_package_resolver.all_package_names
            selection.each do |sel|
                match_pkg_name = Regexp.new(Regexp.quote(sel))
                all_matches = Array.new
                all_source_package_names.each do |pkg_name|
                    pkg = find_autobuild_package(pkg_name)
                    if pkg_name =~ match_pkg_name ||
                        "#{sel}/" =~ Regexp.new("^#{Regexp.quote(pkg.srcdir)}/") ||
                        pkg.srcdir =~ Regexp.new("^#{Regexp.quote(sel)}")
                        all_matches << [pkg_name, (pkg_name == sel || pkg.srcdir == sel)]
                    end
                end
                all_osdeps_package_names.each do |pkg_name|
                    if pkg_name =~ match_pkg_name
                        all_matches << [pkg_name, pkg_name == sel]
                    end
                end

                all_matches.each do |pkg_name, exact_match|
                    # Select packages that are not in the manifest only
                    # if they are explicitely selected. However, we do store
                    # them as "possible resolutions" for the user selection,
                    # and add them if -- at the end of the method -- nothing
                    # has been found for this particular selection
                    if !all_selected_packages.include?(pkg_name) && !exact_match
                        pending_selections[sel] << pkg_name
                    else
                        update_selection(result, sel, pkg_name, true)
                    end
                end
            end

            if options[:filter]
                result.filter_excluded_and_ignored_packages(self)
            end

            nonresolved = selection - result.matches.keys
            nonresolved.delete_if do |sel|
                if pending = pending_selections.fetch(sel, nil)
                    pending.each do |name|
                        update_selection(result, sel, name, true)
                    end
                    true
                end
            end

            return result, nonresolved
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

        # @deprecated use Autoproj.config.each_reused_autoproj_installation
        def each_reused_autoproj_installation
            Autoproj.config.each_reused_autoproj_installation(&proc)
        end

        def reuse(*dir)
            dir = File.expand_path(File.join(*dir), Autoproj.root_dir)
            if reused_installations.any? { |mnf| mnf.path == dir }
                return
            end

            manifest = InstallationManifest.new(dir)
            if !File.file?(manifest.default_manifest_path)
                raise ConfigError.new, "while setting up reuse of #{dir}, the .autoproj-installation-manifest file does not exist. You should probably rerun autoproj envsh in that folder first"
            end
            manifest.load
            @reused_installations << manifest
            manifest.each do |pkg|
                ignore_package pkg.name
            end
        end

        # Load OS dependency information contained in our registered package
        # sets into the provided osdep object
        #
        # @param [OSPackageResolver] osdeps the osdep handling object
        # @return [void]
        def load_osdeps_from_package_sets(osdeps)
            each_package_set do |pkg_set, file|
                osdeps.merge(pkg_set.load_osdeps(file))
            end
        end
    end

    def self.manifest
        Autoproj.warn_deprecated(
            __method__, "use workspace.manifest instead")

        workspace.manifest
    end

    def self.osdeps
        Autoproj.warn_deprecated(
            __method__, "use workspace.os_package_resolver or workspace.os_package_installer instead")

        workspace.os_package_resolver
    end

    def self.config
        Autoproj.warn_deprecated(
            __method__, "use workspace.config instead")

        workspace.config
    end

    def self.add_osdeps_overrides(*args, &block)
        manifest.add_osdeps_overrides(*args, &block)
    end
end

