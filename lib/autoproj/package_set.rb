module Autoproj
    # A package set is a version control repository which contains general
    # information with package version control information (source.yml file),
    # package definitions (.autobuild files), and finally definition of
    # dependencies that are provided by the operating system (.osdeps file).
    class PackageSet
        # Exception raised when an operation that needs the source.yml to be
        # loaded is called before {PackageSet#load_description_file} is called 
        class NotLoaded < RuntimeError
            attr_reader :package_set
            def initialize(package_set)
                @package_set = package_set
            end
        end

        @source_files = ["source.yml"]
        class << self
            attr_reader :source_files

            def master_source_file
                source_files.first
            end

            def add_source_file(name)
                source_files.delete(name)
                source_files << name
            end
        end

        # The underlying workspace
        #
        # @return [Workspace]
        attr_reader :ws

        # The manifest this package set is registered on
        #
        # @return [Manifest] 
        def manifest
            ws.manifest
        end

        # The minimum autoproj version this package set requires
        #
        # It defaults to 0
        #
        # @return [String]
        attr_accessor :required_autoproj_version

        # The package set name
        #
        # @return [String]
        attr_accessor :name

        # The VCSDefinition object that defines the version control holding
        # information for this source. Local package sets (i.e. the ones that are not
        # under version control) use the 'local' version control name. For them,
        # local? returns true.
        attr_accessor :vcs

        # The set of OSPackageResolver object that represent the osdeps files
        # available in this package set
        #
        # @return [Array<(String,OSPackageResolver)>] the list of osdep files
        #   and the corresponding OSPackageResolver object
        attr_reader :all_osdeps

        # The OSPackageResolver which is a merged version of all OSdeps in
        # {#all_osdeps}
        attr_reader :os_package_resolver

        # If this package set has been imported from another package set, this
        # is the other package set object
        attr_accessor :imported_from

        # If true, this package set has been loaded because another set imports
        # it. If false, it is loaded explicitely by the user
        def explicit?; !!@explicit end
        attr_writer :explicit

        # Definition of key => value mappings used to resolve e.g. $KEY values
        # in the version control sections
        attr_reader :constants_definitions

        # The version control information defined in this package set
        attr_reader :version_control

        # The importer that should be used for packages that have no explicit
        # entry
        #
        # @return [VCSDefinition]
        attr_accessor :default_importer

        # The set of overrides defined in this package set
        attr_reader :overrides

        # Sets the auto_imports flag
        #
        # @see auto_imports?
        attr_writer :auto_imports
        # If true (the default), imports listed in this package set will be
        # automatically loaded by autoproj
        def auto_imports?; !!@auto_imports end

        # The VCS definition entries from the 'imports' section of the YAML file
        # @return [Array<VCSDefinition>]
        attr_reader :imports_vcs

        # The package sets that this imports
        attr_reader :imports

        # Returns the Metapackage object that has the same name than this
        # package set
        def metapackage
            manifest.metapackage(name)
        end

        # List of the packages that are built if the package set is selected in
        # the layout
        def default_packages
            metapackage.packages
        end

        # Remote sources can be accessed through a hidden directory in
        # {Workspace#remotes_dir}, or through a symbolic link in
        # autoproj/remotes/
        #
        # This returns the former. See #user_local_dir for the latter.
        #
        # For local sources, is simply returns the path to the source directory.
        attr_reader :raw_local_dir

        # Create this source from a VCSDefinition object
        def initialize(
            ws, vcs,
            name: self.class.name_of(ws, vcs),
            raw_local_dir: self.class.raw_local_dir_of(ws, vcs))

            @ws = ws
            @vcs = vcs
            if !vcs
                raise ArgumentError, "cannot create a package set with a nil vcs, create a null VCS using VCSDefinition.none"
            end
            @name = name
            @os_package_resolver = OSPackageResolver.new(
                operating_system: ws.os_package_resolver.operating_system,
                package_managers: ws.os_package_resolver.package_managers,
                os_package_manager: ws.os_package_resolver.os_package_manager)
            @all_osdeps = []
            @constants_definitions = Hash.new
            @required_autoproj_version = '0'
            @version_control = Array.new
            @overrides = Array.new
            @raw_local_dir = raw_local_dir
            @default_importer = VCSDefinition.from_raw(type: 'none')

            @imports  = Set.new
            @imports_vcs  = Array.new
            @imported_from = Array.new
            @explicit = false
            @auto_imports = true
        end

        # Load a new osdeps file for this package set
        def load_osdeps(file)
            new_osdeps = OSPackageResolver.load(file)
            all_osdeps << new_osdeps
            os_package_resolver.merge(all_osdeps.last)
            new_osdeps
        end

        # Enumerate all osdeps package names from this package set
        def each_osdep(&block)
            os_package_resolver.all_package_names.each(&block)
        end

        # True if this source has already been checked out on the local autoproj
        # installation
        def present?; File.directory?(raw_local_dir) end
        # True if this is the main package set (i.e. the main autoproj
        # configuration)
        def main?; false end
        # True if this source is local, i.e. is not under a version control
        def local?; vcs.local? end
        # True if this source defines nothing
        def empty?
            version_control.empty? && overrides.empty?
                !each_package.find { true } &&
                !File.exist?(File.join(raw_local_dir, "overrides.rb")) &&
                !File.exist?(File.join(raw_local_dir, "init.rb"))
        end

        # Defined for coherence with the API on {PackageDefinition}
        def autobuild
            create_autobuild_package
        end

        # Create a stub autobuild package to handle the import of this package
        # set
        def create_autobuild_package
            Ops::Tools.create_autobuild_package(vcs, name, raw_local_dir)
        end

        def snapshot(target_dir, options = Hash.new)
            if local?
                Hash.new
            else
                package = create_autobuild_package
                if package.importer.respond_to?(:snapshot)
                    package.importer.snapshot(package, target_dir, options)
                end
            end
        end

        # Returns the "best" name under which we can refer to the given package
        # set to the user
        #
        # Mainly, it returns the package set's name if the package set is
        # checked out, and the vcs (as a string) otherwise
        #
        # @return [String]
        def self.name_of(ws, vcs, raw_local_dir: raw_local_dir_of(ws, vcs))
            if File.directory?(raw_local_dir)
                raw_description_file(raw_local_dir, package_set_name: "#{vcs.type}:#{vcs.url}")['name']
            else
                vcs.to_s
            end
        end

        # Returns the local directory in which the given package set should be
        # checked out
        #
        # @param [VCSDefinition] vcs the version control information for the
        #   package set
        # @return [String]
        def self.raw_local_dir_of(ws, vcs)
            if vcs.needs_import?
                repository_id = vcs.create_autobuild_importer.repository_id
                path = File.join(ws.remotes_dir, repository_id.gsub(/[^\w]/, '_'))
                File.expand_path(path)
            elsif !vcs.none?
                File.expand_path(vcs.url)
            end
        end

        # Resolve the VCS information for a package set
        #
        # This parses the information stored in the package_sets section of
        # autoproj/manifest, or the imports section of the source.yml files and
        # returns the corresponding VCSDefinition object
        def self.resolve_definition(ws, raw_spec)
            spec = VCSDefinition.normalize_vcs_hash(raw_spec, base_dir: ws.config_dir)
            options, vcs_spec = Kernel.filter_options spec, auto_imports: true

            vcs_spec = Autoproj.expand(vcs_spec, ws.manifest.constant_definitions)
            return VCSDefinition.from_raw(vcs_spec, raw: [[nil, raw_spec]]), options
        end

        # Returns a string that uniquely represents the version control
        # information for this package set.
        #
        # I.e. for two package sets set1 and set2, if set1.repository_id ==
        # set2.repository_id, it means that both package sets are checked out
        # from exactly the same source.
        def repository_id
            if local?
                raw_local_dir
            else
                importer = vcs.create_autobuild_importer
                if importer.respond_to?(:repository_id)
                    importer.repository_id
                else
                    vcs.to_s
                end
            end
        end

        # Remote sources can be accessed through a hidden directory in
        # {Workspace#remotes_dir}, or through a symbolic link in
        # autoproj/remotes/
        #
        # This returns the latter. See #raw_local_dir for the former.
        #
        # For local sources, is simply returns the path to the source directory.
        def user_local_dir
            if local?
                return vcs.url 
            else
                File.join(ws.config_dir, 'remotes', name)
            end
        end

        # The directory in which data for this source will be checked out
        def local_dir
            ugly_dir   = raw_local_dir
            pretty_dir = user_local_dir
            if ugly_dir == pretty_dir
                pretty_dir
            elsif File.symlink?(pretty_dir) && File.readlink(pretty_dir) == ugly_dir
                pretty_dir
            else
                ugly_dir
            end
        end

        # @api private
        #
        # Read the description information for a package set in a given
        # directory
        #
        # @param [String] raw_local_dir the package set's directory
        # @return [Hash] the raw description information
        def self.raw_description_file(raw_local_dir, package_set_name: nil)
            master_source_file = File.join(raw_local_dir, PackageSet.master_source_file)
            if !File.exist?(master_source_file)
                raise ConfigError.new, "package set #{package_set_name} present in #{raw_local_dir} should have a source.yml file, but does not"
            end

            source_definition = Hash.new
            PackageSet.source_files.each do |name|
                source_file = File.join(raw_local_dir, name)
                next if !File.file?(source_file)

                newdefs = Autoproj.in_file(source_file, Autoproj::YAML_LOAD_ERROR) do
                    YAML.load(File.read(source_file))
                end
                source_definition.merge!(newdefs || Hash.new) do |k, old, new|
                    if old.respond_to?(:to_ary)
                        old + new
                    else new
                    end
                end
            end
            if !source_definition['name']
                raise ConfigError.new(master_source_file), "#{master_source_file} does not have a 'name' field"
            end
            source_definition
        end

        # Loads the source.yml file, validates it and returns it as a hash
        #
        # Raises InternalError if the source has not been checked out yet (it
        # should have), and ConfigError if the source.yml file is not valid.
        def raw_description_file
            if !present?
                raise InternalError, "source #{vcs} has not been fetched yet, cannot load description for it"
            end

            self.class.raw_description_file(raw_local_dir, package_set_name: name)
        end

        # Yields the package sets imported by this package set
        #
        # This information is available only after the whole configuration has
        # been loaded
        #
        # @yieldparam [PackageSet] pkg_set a package set imported by this one
        def each_imported_set(&block)
            @imports.each(&block)
        end

        # Add a new constant to be used to resolve e.g. version control entries
        def add_constant_definition(key, value)
            constants_definitions[key] = value
        end

        # Add a new VCS import to the list of imports
        #
        # @param [VCSDefinition] vcs the VCS specification for the import
        # @return [void]
        def add_raw_imported_set(vcs, auto_imports: true)
            imports_vcs << [vcs, Hash[auto_imports: auto_imports]]
        end

        # Yields the imports raw information
        #
        # @yieldparam [VCSDefinition] vcs the import VCS information
        # @yieldparam [Hash] options import options
        def each_raw_imported_set(&block)
            imports_vcs.each(&block)
        end

        # Add a new entry in the list of version control resolutions
        def add_version_control_entry(matcher, vcs_definition)
            version_control << [matcher, vcs_definition]
        end

        # Add a new entry in the list of version control resolutions
        def add_overrides_entry(matcher, vcs_definition, file: '#add_overrides_entry')
            if (last_entry = overrides.last) && last_entry[0] == file
                last_entry[1] << [matcher, vcs_definition]
            else
                overrides << [file, [[matcher, vcs_definition]]]
            end
        end

        # Path to the source.yml file
        def source_file
            if local_dir
                File.join(local_dir, 'source.yml')
            end
        end

        # Load the source.yml file and resolves all information it contains.
        def load_description_file
            source_definition = raw_description_file
            name = source_definition['name']
            if name !~ /^[\w\.-]+$/
                raise ConfigError.new(source_file),
                    "in #{source_file}: invalid source name '#{@name}': source names can only contain alphanumeric characters, and .-_"
            elsif name == "local"
                raise ConfigError.new(source_file),
                    "in #{source_file}: the name 'local' is a reserved name"
            end

            parse_source_definition(source_definition)
        end

        def load_overrides(source_definition)
            if data = source_definition['overrides']
                [[source_file, data]]
            end
        end

        def parse_source_definition(source_definition)
            @name = source_definition['name'] || self.name
            @required_autoproj_version = source_definition.fetch('required_autoproj_version', self.required_autoproj_version)
            if new_imports = source_definition['imports']
                @imports_vcs  = Array(new_imports).map do |set_def|
                    if !set_def.kind_of?(Hash) && !set_def.respond_to?(:to_str)
                        raise ConfigError.new(source_file),
                            "in #{source_file}: wrong format for 'imports' section. Expected an array of maps or strings (e.g. - github: my/url)."
                    end

                    Autoproj.in_file(source_file) do
                        PackageSet.resolve_definition(ws, set_def)
                    end
                end
            end

            # Compute the definition of constants
            if new_constants = source_definition['constants']
                Autoproj.in_file(source_file) do
                    variables = inject_constants_and_config_for_expansion(Hash.new)
                    @constants_definitions = Autoproj.resolve_constant_definitions(new_constants, variables)
                end
            end

            if new_version_control = source_definition['version_control']
                @version_control = normalize_vcs_list('version_control', source_file, new_version_control)

                Autoproj.in_file(source_file) do
                    default_vcs_spec, raw = version_control_field('default', version_control)
                    if default_vcs_spec
                        @default_importer = VCSDefinition.from_raw(default_vcs_spec, raw: raw, from: self)
                    end
                end
            end
            if new_overrides = load_overrides(source_definition)
                @overrides = new_overrides.map do |file, entries|
                    [file, normalize_vcs_list('overrides', file, entries)]
                end
            end
        end

        # @api private
        #
        # Injects the values of {#constants_definitions} and
        # {#manifest}.constant_definitions, as well as the available
        # configuration variables, into a hash suitable to be used for variable
        # expansion using {Autoproj.expand} and {Autoproj.single_expansion}
        def inject_constants_and_config_for_expansion(additional_expansions)
            defs = additional_expansions.
                merge(constants_definitions).
                merge(manifest.constant_definitions)

            config = ws.config
            Hash.new do |h, k|
                if config.has_value_for?(k) || config.declared?(k)
                    config.get(k)
                end
            end.merge(defs)
        end

        def single_expansion(data, additional_expansions = Hash.new)
            defs = inject_constants_and_config_for_expansion(additional_expansions)
            Autoproj.single_expansion(data, defs)
        end

        # Expands the given string as much as possible using the expansions
        # listed in the source.yml file, and returns it. Raises if not all
        # variables can be expanded.
        def expand(data, additional_expansions = Hash.new)
            defs = inject_constants_and_config_for_expansion(additional_expansions)
            Autoproj.expand(data, defs)
        end

        # @api private
        #
        # Converts a number to an ordinal string representation (i.e. 1st, 25th)
        def number_to_nth(number)
            Hash[1 => '1st', 2 => '2nd', 3 => '3rd'].fetch(number, "#{number}th")
        end

        # @api private
        #
        # Validate the format of a VCS list field (formatted in array-of-hashes)
        def normalize_vcs_list(section_name, file, list)
            if list.kind_of?(Hash)
                raise InvalidYAMLFormatting, "wrong format for the #{section_name} section of #{file}, you forgot the '-' in front of the package names"
            elsif !list.kind_of?(Array)
                raise InvalidYAMLFormatting, "wrong format for the #{section_name} section of #{file}"
            end

            list.each_with_index.map do |spec, spec_idx|
                spec_nth = number_to_nth(spec_idx + 1)
                if !spec.kind_of?(Hash)
                    raise InvalidYAMLFormatting, "wrong format for the #{spec_nth} entry (#{spec.inspect}) of the #{section_name} section of #{file}, expected a package name, followed by a colon, and one importer option per following line"
                end

                spec = spec.dup
                if spec.values.size != 1
                    # Maybe the user wrote the spec like
                    #   - package_name:
                    #     type: git
                    #     url: blah
                    #
                    # In that case, we should have the package name as
                    # "name => nil". Check that.
                    name, _ = spec.find { |n, v| v.nil? }
                    if name
                        spec.delete(name)
                    else
                        raise InvalidYAMLFormatting, "cannot make sense of the #{spec_nth} entry in the #{section_name} section of #{file}: #{spec}"
                    end
                else
                    name, spec = spec.to_a.first
                    if spec.respond_to?(:to_str)
                        if spec == "none"
                            spec = Hash['type' => "none"]
                        else
                            raise ConfigError.new, "invalid VCS specification in the #{section_name} section of #{file}: '#{name}: #{spec}'. One can only use this shorthand to declare the absence of a VCS with the 'none' keyword"
                        end
                    elsif !spec.kind_of?(Hash)
                        raise InvalidYAMLFormatting, "expected '#{name}:' followed by version control options, but got nothing, in the #{spec_nth} entry of the #{section_name} section of #{file}"
                    end
                end

                name_match = name
                if name_match =~ /[^\w\/-]/
                    name_match = Regexp.new("^" + name_match)
                end
                [name_match, spec]
            end
        end

        # Returns an importer definition for the given package, if one is
        # available. Otherwise returns nil.
        #
        # The returned value is a VCSDefinition object.
        def version_control_field(package_name, entry_list, validate = true)
            raw = []
            vcs_spec = Hash.new

            entry_list.each do |name_match, spec|
                if name_match === package_name
                    raw << [self, spec]
                    vcs_spec =
                        begin
                            VCSDefinition.update_raw_vcs_spec(vcs_spec, spec)
                        rescue ConfigError => e
                            raise ConfigError.new, "invalid VCS definition in the #{section_name} section for '#{name}': #{e.message}", e.backtrace
                        end
                end
            end

            if vcs_spec.empty?
                return nil, []
            end

            expansions = Hash["PACKAGE" => package_name,
                "PACKAGE_BASENAME" => File.basename(package_name),
                "AUTOPROJ_ROOT" => ws.root_dir,
                "AUTOPROJ_CONFIG" => ws.config_dir,
                "AUTOPROJ_SOURCE_DIR" => local_dir]

            vcs_spec = expand(vcs_spec, expansions)
            vcs_spec.dup.each do |name, value|
                vcs_spec[name] = expand(value, expansions)
            end

            # If required, verify that the configuration is a valid VCS
            # configuration
            if validate
                begin
                    VCSDefinition.from_raw(vcs_spec)
                rescue ConfigError => e
                    raise ConfigError.new, "invalid resulting VCS definition for package #{package_name}: #{e.message}", e.backtrace
                end
            end
            return vcs_spec, raw
        end

        # Returns the VCS definition for +package_name+ as defined in this
        # source, or nil if the source does not have any.
        #
        # @param [PackageDefinition] package
        # @return [VCSDefinition] the importer definition, or nil if none
        #   could be found
        def importer_definition_for(package, default: default_importer, require_existing: true)
            package_name = manifest.validate_package_name_argument(package, require_existing: require_existing)
            Autoproj.in_file source_file do
                vcs_spec, raw = version_control_field(package_name, version_control)
                if vcs_spec
                    VCSDefinition.from_raw(vcs_spec, raw: raw, from: self)
                else
                    default
                end
            end
        end

        # Update a VCS object using the overrides defined in this package set
        #
        # @param [PackageDefinition] package the package
        # @param [VCSDefinition] the vcs to be updated
        # @return [VCSDefinition] the new, updated vcs object
        def overrides_for(package, vcs, require_existing: true)
            package_name = manifest.validate_package_name_argument(package, require_existing: require_existing)
            resolve_overrides(package_name, vcs)
        end

        # @api private
        #
        # Apply overrides on a VCS object from its (string) key
        #
        # This is a helper for {#overrides_for}
        def resolve_overrides(key, vcs)
            overrides.each do |file, file_overrides|
                new_spec, new_raw_entry = 
                    Autoproj.in_file file do
                        version_control_field(key, file_overrides, false)
                    end

                if new_spec
                    Autoproj.in_file file do
                        begin
                            vcs = vcs.update(new_spec, raw: new_raw_entry, from: self)
                        rescue ConfigError => e
                            raise ConfigError.new, "invalid resulting VCS specification in the overrides section for #{key}: #{e.message}"
                        end
                    end
                end
            end
            vcs
        end

        # Enumerates the Autobuild::Package instances that are defined in this
        # source
        def each_package
            if !block_given?
                return enum_for(:each_package)
            end

            manifest.packages.each_value do |pkg|
                if pkg.package_set.name == name
                    yield(pkg.autobuild)
                end
            end
        end

        # List the autobuild files that are part of this package set
        def each_autobuild_file
            return enum_for(__method__) if !block_given?
            Dir.glob(File.join(local_dir, "*.autobuild")).sort.each do |file|
                yield(file)
            end
        end

        # Yields each osdeps definition files that are present in this package
        # set
        def each_osdeps_file
            return enum_for(__method__) if !block_given?
            Dir.glob(File.join(local_dir, "*.osdeps")).each do |file|
                yield(file)
            end
        end
    end
end

