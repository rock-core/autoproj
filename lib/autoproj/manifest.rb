require 'yaml'
require 'csv'
require 'utilrb/kernel/options'
require 'set'
require 'rexml/document'

require 'win32/dir' if RbConfig::CONFIG["host_os"] =~%r!(msdos|mswin|djgpp|mingw|[Ww]indows)! 

module Autoproj
    @build_system_dependencies = Set.new

    # Declare OS packages that are required to import and build the packages
    #
    # It is used by autoproj itself to install the importers and/or the build
    # systems for the packages.
    def self.add_build_system_dependency(*names)
        @build_system_dependencies |= names.to_set
    end

    class << self
        # Returns the set of OS packages that are needed to build and/or import
        # the packages
        #
        # See Autoproj.add_build_system_dependency
        attr_reader :build_system_dependencies
    end

    # The Manifest class represents the information included in the main
    # manifest file, and allows to manipulate it
    class Manifest
        # The set of packages that are selected by the user, either through the
        # manifest file or through the command line, as a set of package names
        attr_accessor :explicit_selection

        # Set the package sets that are available on this manifest
        #
        # This is set externally at loading time. {load_and_update_package_sets}
        # can do it as well
        #
        # @return [Array<PackageSet>]
        attr_writer :package_sets

        # Returns true if +pkg_name+ has been explicitely selected
        def explicitly_selected_package?(pkg_name)
            explicit_selection && explicit_selection.include?(pkg_name)
        end

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
            @ignored_packages |= (data['ignored_packages'] || Set.new)
            data['exclude_packages'] ||= Set.new

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
        attr_reader :vcs

        # The definition of all OS packages available on this installation
        attr_reader :osdeps

	def initialize
            @file = nil
	    @data = Hash.new
            @packages = Hash.new
            @package_manifests = Hash.new
            @package_sets = []
            @osdeps = OSDependencies.new

            @automatic_exclusions = Hash.new
            @constants_definitions = Hash.new
            @disabled_imports = Set.new
            @moved_packages = Hash.new
            @osdeps_overrides = Hash.new
            @metapackages = Hash.new
            @ignored_os_dependencies = Set.new
            @reused_installations = Array.new
            @ignored_packages = Set.new

            @constant_definitions = Hash.new
            if Autoproj.has_config_key?('manifest_source')
                @vcs = VCSDefinition.from_raw(Autoproj.user_config('manifest_source'))
            end
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
        def each_ignored_package
            ignored_packages.each do |l|
                if pkg_set = metapackages[l]
                    pkg_set.each_package do |pkg|
                        yield(pkg.name)
                    end
                else
                    yield(l)
                end
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
            data['exclude_packages']
        end

        # A package_name => reason map of the exclusions added with #add_exclusion.
        # Exclusions listed in the manifest file are returned by #manifest_exclusions
        attr_reader :automatic_exclusions

        # Exclude +package_name+ from the build. +reason+ is a string describing
        # why the package is to be excluded.
        def add_exclusion(package_name, reason)
            automatic_exclusions[package_name] = reason
        end

        # If +package_name+ is excluded from the build, returns a string that
        # tells why. Otherwise, returns nil
        #
        # Packages can either be excluded because their name is listed in the
        # exclude_packages section of the manifest, or because they are
        # disabled on this particular operating system.
        def exclusion_reason(package_name)
            if manifest_exclusions.any? { |l| Regexp.new(l) =~ package_name }
                "#{package_name} is listed in the exclude_packages section of the manifest"
            else
                automatic_exclusions[package_name]
            end
        end

        # True if the given package should not be built and its dependencies
        # should be considered as met.
        #
        # This is useful to avoid building packages that are of no use for the
        # user.
        def excluded?(package_name)
            if manifest_exclusions.any? { |l| Regexp.new(l) =~ package_name }
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

                Dir.glob(File.join(source.local_dir, "*.autobuild")).each do |file|
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
            Ops::Configuration.new(self, Ops.loader).load_and_update_package_sets
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
        def register_package(package, block, source, file)
            pkg = PackageDefinition.new(package, source, file)
            if block
                pkg.add_setup_block(block)
            end
            @packages[package.name] = pkg
            @metapackages[pkg.package_set.name].add(pkg.autobuild)
            @metapackages["#{pkg.package_set.name}.all"].add(pkg.autobuild)
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
            packages[name]
        end

        def find_autobuild_package(name)
            if pkg = packages[name]
                pkg.autobuild
            end
        end

        def package(name)
            packages[name]
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
            Ops::Tools.create_autobuild_package(vcs, text_name, into)
        end

        # @deprecated use Ops::Configuration#update_main_configuration
        def update_yourself(only_local = false)
            Ops::Configuration.new(self, Ops.loader).update_main_configuration(only_local)
        end

        # @deprecated use Ops::Configuration.update_remote_package_set
        def update_remote_set(vcs, only_local = false)
            Ops::Configuration.update_remote_package_set(vcs, only_local)
        end

        # Compute the VCS definition for a given package
        #
        # @param [String] package_name the name of the package to be resolved
        # @param [PackageSet,nil] package_source the package set that defines the
        #   given package, defaults to the package's definition source (as
        #   returned by {definition_package_set}) if not given
        # @return [VCSDefinition] the VCS definition object
        def importer_definition_for(package_name, package_source = definition_package_set(package_name))
            vcs = package_source.importer_definition_for(package_name)
            return if !vcs

            # Get the sets that come *after* the one that defines the package to
            # apply the overrides
            package_sets = each_package_set.to_a.dup
            while !package_sets.empty? && package_sets.first != package_source
                package_sets.shift
            end
            package_sets.shift

            # Then apply the overrides
            package_sets.inject(vcs) do |updated_vcs, pkg_set|
                pkg_set.overrides_for(package_name, updated_vcs)
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
        def load_importers
            packages.each_value do |pkg|
                vcs = importer_definition_for(pkg.autobuild.name, pkg.package_set) ||
                    pkg.package_set.default_importer

                if vcs
                    Autoproj.add_build_system_dependency vcs.type
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
            set = each_package_set(false).find { |set| set.name == name }
            if !set
                raise ArgumentError, "no package set called #{name} exists"
            end
            set
        end

        def main_package_set
            each_package_set.find(&:main?)
        end

        # Exception raised when a caller requires to use an excluded package
        class ExcludedPackage < ConfigError
            attr_reader :name
            def initialize(name)
                @name = name
            end
        end

        # Resolves the given +name+, where +name+ can either be the name of a
        # source or the name of a package.
        #
        # The returned value is a list of pairs:
        #
        #   [type, package_name]
        #
        # where +type+ can either be :package or :osdeps (as symbols)
        #
        # The returned array can be empty if +name+ is an ignored package
        def resolve_package_name(name, options = Hash.new)
            if pkg_set = find_metapackage(name)
                pkg_names = pkg_set.each_package.map(&:name)
            else
                pkg_names = [name]
            end

            result = []
            pkg_names.each do |pkg|
                result.concat(resolve_single_package_name(pkg, options))
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

                pkg = Autobuild::Package[pkg_name]
                pkg.dependencies.each do |dep_name|
                    queue << dep_name
                end
            end
            result
        end

        # Resolves a package name, where +name+ cannot be resolved as a
        # metapackage
        #
        # This is a helper method for #resolve_package_name. Do not use
        # directly
        def resolve_single_package_name(name, options = Hash.new) # :nodoc:
            options = Kernel.validate_options options, :filter => true

            explicit_selection  = explicitly_selected_package?(name)
	    osdeps_availability = osdeps.availability_of(name)
            available_as_source = Autobuild::Package[name]

            osdeps_overrides = Autoproj.manifest.osdeps_overrides[name]
            if osdeps_overrides
                source_packages    = osdeps_overrides[:packages].dup
                force_source_usage = osdeps_overrides[:force]
                begin
                    source_packages = source_packages.inject([]) do |result, src_pkg_name|
                        result.concat(resolve_package_name(src_pkg_name))
                    end.uniq
                    available_as_source = true
                rescue ExcludedPackage
                    force_source_usage = false
                    available_as_source = false
                end

                if source_packages.empty?
                    source_packages << [:package, name]
                end
            end

            if force_source_usage
                return source_packages
            elsif !explicit_selection 
                if osdeps_availability == Autoproj::OSDependencies::AVAILABLE
                    return [[:osdeps, name]]
                elsif osdeps_availability == Autoproj::OSDependencies::IGNORE
                    return []
                end

                if osdeps_availability == Autoproj::OSDependencies::UNKNOWN_OS
                    # If we can't handle that OS, but other OSes have a
                    # definition for it, we assume that it can be installed as
                    # an external package. However, if it is also available as a
                    # source package, prompt the user
                    if !available_as_source || explicit_osdeps_selection(name)
                        return [[:osdeps, name]]
                    end
                end

                # No source, no osdeps.
                # If the package is ignored by the manifest, just return empty.
                # Otherwise, generate a proper error message
                # Call osdeps again, but this time to get
                # a proper error message.
                if !available_as_source
                    if ignored?(name)
                        return []
                    end
                    begin
                        osdeps.resolve_os_dependencies([name].to_set)
                    rescue Autoproj::ConfigError => e
                        if osdeps_availability != Autoproj::OSDependencies::NO_PACKAGE && !osdeps.os_package_handler.enabled?
                            if !@ignored_os_dependencies.include?(name)
                                Autoproj.warn "some package depends on the #{name} osdep: #{e.message}"
                                Autoproj.warn "this osdeps dependency is simply ignored as you asked autoproj to not install osdeps packages"
                                @ignored_os_dependencies << name
                            end
                            # We are not asked to install OS packages, just ignore
                            return []
                        end
                        raise
                    end
                    # Should never reach further than that
                end
            elsif !available_as_source
                raise ConfigError, "cannot resolve #{name}: it is not a package, not a metapackage and not an osdeps"
            end
            if source_packages
                return source_packages
            else
                return [[:package, name]]
            end
        end

        # +name+ can either be the name of a source or the name of a package. In
        # the first case, we return all packages defined by that source. In the
        # latter case, we return the singleton array [name]
        def resolve_package_set(name)
            if Autobuild::Package[name]
                [name]
            else
                pkg_set = find_metapackage(name)
                if !pkg_set
                    raise UnknownPackage.new(name), "#{name} is neither a package nor a package set name. Packages in autoproj must be declared in an autobuild file."
                end
                pkg_set.each_package.
                    map(&:name).
                    find_all { |pkg_name| !osdeps || !osdeps.has?(pkg_name) }
            end
        end

        def find_metapackage(name)
            @metapackages[name.to_s]
        end

        # call-seq:
        #   metapackage 'meta_name' => Metapackage
        #   metapackage 'meta_name', 'pkg1', 'pkg2' => Metapackage
        #
        # Metapackage definition
        #
        # In the first form, returns a Metapackage instance for the metapackage
        # named 'meta_name'.
        #
        # In the second form, adds the listed packages to the metapackage and
        # returns the Metapackage instance
        def metapackage(name, *packages, &block)
            meta = (@metapackages[name.to_s] ||= Metapackage.new(name))
            packages.each do |pkg_name|
                package_names = resolve_package_set(pkg_name)
                package_names.each do |pkg_name|
                    meta.add(Autobuild::Package[pkg_name])
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


                        result.select(pkg_or_set, resolve_package_set(pkg_or_set), weak)
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
            Autobuild::Package.each.map { |name, _| name }.to_set
        end

        # Returns all the packages that can be built in this installation
        def all_packages
            result = Set.new
            each_package_set do |pkg_set|
                result |= metapackage(pkg_set.name).packages.map(&:name).to_set
            end
            result.to_a.
                find_all { |pkg_name| !osdeps.has?(pkg_name) }
        end

        # Returns true if +name+ is a valid package and is included in the build
        #
        # If +validate+ is true, the method will raise ArgumentError if the
        # package does not exists. 
        #
        # If it is false, the method will simply return false on non-defined
        # packages 
        def package_enabled?(name, validate = true)
            if !Autobuild::Package[name] && !osdeps.has?(name)
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
            root = default_packages(validate).packages.to_set
            root.each do |pkg_name|
                Autobuild::Package[pkg_name].all_dependencies(result)
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

        def normalized_layout(result = Hash.new, layout_level = '/', layout_data = (data['layout'] || Hash.new))
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
        def load_package_manifest(pkg_name)
            pkg = packages.values.
                find { |pkg| pkg.autobuild.name == pkg_name }
            package, package_set, file = pkg.autobuild, pkg.package_set, pkg.file

            if !pkg_name
                raise ArgumentError, "package #{pkg_name} is not defined"
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
        #   list_os_dependencies(packages) => required_packages, ospkg_to_pkg
        #
        # Returns the set of dependencies required by the listed packages.
        #
        # +required_packages+ is the set of osdeps names that are required for
        # +packages+ and +ospkg_to_pkg+ a mapping from the osdeps name to the
        # set of packages that require this OS package.
        def list_os_dependencies(packages)
            required_os_packages = Set.new
            package_os_deps = Hash.new { |h, k| h[k] = Array.new }
            packages.each do |pkg_name|
                pkg = Autobuild::Package[pkg_name]
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

        def filter_os_dependencies(required_os_packages, package_os_deps)
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

        # Restores the OS dependencies required by the given packages to
        # pristine conditions
        #
        # This is usually called as a rebuild step to make sure that all these
        # packages are updated to whatever required the rebuild
        def pristine_os_dependencies(packages)
            required_os_packages, package_os_deps = list_os_dependencies(packages)
            required_os_packages =
                filter_os_dependencies(required_os_packages, package_os_deps)
            osdeps.pristine(required_os_packages)
        end

        # Installs the OS dependencies that are required by the given packages
        def install_os_dependencies(packages)
            required_os_packages, package_os_deps = list_os_dependencies(packages)
            required_os_packages =
                filter_os_dependencies(required_os_packages, package_os_deps)
            osdeps.install(required_os_packages)
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
        def add_osdeps_overrides(osdeps_name, options)
            options = Kernel.validate_options options, :package => nil, :packages => [], :force => false
            if pkg = options.delete(:package)
                options[:packages] << pkg
            end
            @osdeps_overrides[osdeps_name.to_s] = options
        end

        # Remove any OSDeps override that has previously been added with
        # #add_osdeps_overrides
        def remove_osdeps_overrides(osdep_name)
            @osdeps_overrides.delete(osdeps_name.to_s)
        end

        # Exception raised when an unknown package is encountered
        class UnknownPackage < ConfigError
            attr_reader :name
            def initialize(name)
                @name = name
            end
        end

        PackageSelection = Autoproj::PackageSelection

        # Package selection can be done in three ways:
        #  * as a subdirectory in the layout
        #  * as a on-disk directory
        #  * as a package name
        #
        # This method converts the first two directories into the third one
        def expand_package_selection(selection, options = Hash.new)
            options = Kernel.validate_options options, filter: true

            result = PackageSelection.new

            # All the packages that are available on this installation
            all_layout_packages = self.all_selected_packages

            # First, remove packages that are directly referenced by name or by
            # package set names
            selection.each do |sel|
                match_pkg_name = Regexp.new(Regexp.quote(sel))

                packages = all_layout_packages.
                    find_all { |pkg_name| pkg_name =~ match_pkg_name }.
                    to_set
                if !packages.empty?
                    result.select(sel, packages)
                end

                each_metapackage do |pkg|
                    if pkg.name =~ match_pkg_name
                        packages = resolve_package_set(pkg.name).to_set
                        packages = (packages & all_layout_packages)
                        result.select(sel, packages, pkg.weak_dependencies?)
                    end
                end
            end

            pending_selections = Hash.new

            # Finally, check for package source directories
            all_packages = self.all_package_names
            all_osdeps_packages = osdeps.all_package_names

            selection.each do |sel|
                match_pkg_name = Regexp.new(Regexp.quote(sel))
                matching_packages = all_packages.map do |pkg_name|
                    pkg = Autobuild::Package[pkg_name]
                    if pkg_name =~ match_pkg_name ||
                        "#{sel}/" =~ Regexp.new("^#{Regexp.quote(pkg.srcdir)}/") ||
                        pkg.srcdir =~ Regexp.new("^#{Regexp.quote(sel)}")
                        [pkg_name, (pkg_name == sel || pkg.srcdir == sel)]
                    end
                end.compact
                matching_osdeps_packages = all_osdeps_packages.find_all do |pkg_name|
                    if pkg_name =~ match_pkg_name
                        [pkg_name, pkg_name == sel]
                    end
                end.compact

                (matching_packages + matching_osdeps_packages).to_set.each do |pkg_name, exact_match|
                    # Check-out packages that are not in the manifest only
                    # if they are explicitely selected. However, we do store
                    # them as "possible resolutions" for the user selection,
                    # and add them if -- at the end of the method -- nothing
                    # has been found for this particular selection
                    if !all_layout_packages.include?(pkg_name) && !exact_match
                        pending_selections[sel] = pkg_name
                        next
                    end

                    result.select(sel, pkg_name)
                end
            end

            if options[:filter]
                result.filter_excluded_and_ignored_packages(self)
            end
            nonresolved = selection - result.matches.keys
            nonresolved.delete_if do |sel|
                if pkg_name = pending_selections[sel]
                    result.select(sel, pkg_name)
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
        # @param [OSDependencies] osdeps the osdep handling object
        # @return [void]
        def load_osdeps_from_package_sets(osdeps)
            each_osdeps_file do |source, file|
                osdeps.merge(source.load_osdeps(file))
            end
        end
    end

    class << self
        # The singleton manifest object that represents the current build
        # configuration
        #
        # @return [Manifest]
        attr_accessor :manifest

        # The known osdeps definitions
        #
        # @return [OSDependencies]
        # @see load_osdeps_from_package_sets
        def osdeps
            manifest.osdeps
        end

        def osdeps=(osdeps)
            raise ArgumentError, "cannot set the osdeps object explicitely anymore. Use osdeps.clear and osdeps.merge"
        end

        # The configuration file
        # @return [Configuration]
        attr_accessor :config
    end

    # Load the osdeps files contained in {manifest} into {osdeps}
    def self.load_osdeps_from_package_sets
        manifest.load_osdeps_from_package_sets(osdeps)
        osdeps
    end

    def self.add_osdeps_overrides(*args, &block)
        manifest.add_osdeps_overrides(*args, &block)
    end
end

