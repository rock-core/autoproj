module Autoproj
    # A package set is a version control repository which contains general
    # information with package version control information (source.yml file),
    # package definitions (.autobuild files), and finally definition of
    # dependencies that are provided by the operating system (.osdeps file).
    class PackageSet
        attr_reader :manifest
        # The VCSDefinition object that defines the version control holding
        # information for this source. Local package sets (i.e. the ones that are not
        # under version control) use the 'local' version control name. For them,
        # local? returns true.
        attr_accessor :vcs

        # The set of OSDependencies object that represent the osdeps files
        # available in this package set
        attr_reader :all_osdeps

        # The OSDependencies which is a merged version of all OSdeps in
        # #all_osdeps
        attr_reader :osdeps

        # If this package set has been imported from another package set, this
        # is the other package set object
        attr_accessor :imported_from

        # If true, this package set has been loaded because another set imports
        # it. If false, it is loaded explicitely by the user
        def explicit?; !@imported_from end

        attr_reader :source_definition
        attr_reader :constants_definitions

        # Sets the auto_imports flag. See #auto_imports?
        attr_writer :auto_imports
        # If true (the default), imports listed in this package set will be
        # automatically loaded by autoproj
        def auto_imports?; !!@auto_imports end

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

        # Create this source from a VCSDefinition object
        def initialize(manifest, vcs)
            @manifest = manifest
            @vcs = vcs
            @osdeps = OSDependencies.new
            @all_osdeps = []

            @provides = Set.new
            @imports  = Array.new
            @auto_imports = true
        end

        # Load a new osdeps file for this package set
        def load_osdeps(file)
            new_osdeps = OSDependencies.load(file)
            @all_osdeps << new_osdeps
            @osdeps.merge(@all_osdeps.last)
            new_osdeps
        end

        # Enumerate all osdeps package names from this package set
        def each_osdep(&block)
            @osdeps.definitions.each_key(&block)
        end

        # True if this source has already been checked out on the local autoproj
        # installation
        def present?; File.directory?(raw_local_dir) end
        # True if this source is local, i.e. is not under a version control
        def local?; vcs.local? end
        # True if this source defines nothing
        def empty?
            !source_definition['version_control'] && !source_definition['overrides']
                !each_package.find { true } &&
                !File.exists?(File.join(raw_local_dir, "overrides.rb")) &&
                !File.exists?(File.join(raw_local_dir, "init.rb"))
        end

        def snapshot(target_dir)
            if local?
                Hash.new
            else
                package = Manifest.create_autobuild_package(vcs, name, raw_local_dir)
                package.importer.snapshot(package, target_dir)
            end
        end

        # Create a PackageSet instance from its description as found in YAML
        # configuration files
        def self.from_spec(manifest, raw_spec, load_description)
            if raw_spec.respond_to?(:to_str)
                local_path = File.join(Autoproj.config_dir, raw_spec)
                if File.directory?(local_path)
                    raw_spec = { :type => 'local', :url => local_path }
                end
            end
            spec = VCSDefinition.vcs_definition_to_hash(raw_spec)
            options, vcs_spec = Kernel.filter_options spec, :auto_imports => true

            # Look up for short notation (i.e. not an explicit hash). It is
            # either vcs_type:url or just url. In the latter case, we expect
            # 'url' to be a path to a local directory
            vcs_spec = Autoproj.expand(vcs_spec, manifest.constant_definitions)
            vcs_def  = VCSDefinition.from_raw(vcs_spec, [[nil, raw_spec]])

            source = PackageSet.new(manifest, vcs_def)
            source.auto_imports = options[:auto_imports]
            if load_description
                if source.present?
                    source.load_description_file
                else
                    raise InternalError, "cannot load description file as it has not been checked out yet"
                end
            else
                # Try to load just the name from the source.yml file
                source.load_minimal
            end

            source
        end

        # Returns a string that uniquely represents the version control
        # information for this package set.
        #
        # I.e. for two package sets set1 and set2, if set1.repository_id ==
        # set2.repository_id, it means that both package sets are checked out
        # from exactly the same source.
        def repository_id
            if local?
                local_dir
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
        # $AUTOPROJ_ROOT/.remotes, or through a symbolic link in
        # autoproj/remotes/
        #
        # This returns the former. See #user_local_dir for the latter.
        #
        # For local sources, is simply returns the path to the source directory.
        def raw_local_dir
            if local?
                File.expand_path(vcs.url)
            else
                File.expand_path(File.join(Autoproj.remotes_dir, vcs.create_autobuild_importer.repository_id.gsub(/[^\w]/, '_')))
            end
        end

        # Remote sources can be accessed through a hidden directory in
        # $AUTOPROJ_ROOT/.remotes, or through a symbolic link in
        # autoproj/remotes/
        #
        # This returns the latter. See #raw_local_dir for the former.
        #
        # For local sources, is simply returns the path to the source directory.
        def user_local_dir
            if local?
                return vcs.url 
            else
                File.join(Autoproj.config_dir, 'remotes', name)
            end
        end

        # The directory in which data for this source will be checked out
        def local_dir
            ugly_dir   = raw_local_dir
            pretty_dir = user_local_dir
            if File.symlink?(pretty_dir) && File.readlink(pretty_dir) == ugly_dir
                pretty_dir
            else
                ugly_dir
            end
        end

        def required_autoproj_version
            definition = @source_definition || raw_description_file
            definition['required_autoproj_version'] || '0'
        end

        # Returns the source name
        def name
            if @name
                @name
            else
                vcs.to_s
            end
        end

        # Loads the source.yml file, validates it and returns it as a hash
        #
        # Raises InternalError if the source has not been checked out yet (it
        # should have), and ConfigError if the source.yml file is not valid.
        def raw_description_file
            if !present?
                raise InternalError, "source #{vcs} has not been fetched yet, cannot load description for it"
            end

            source_file = File.join(raw_local_dir, "source.yml")
            if !File.exists?(source_file)
                raise ConfigError.new, "source #{vcs.type}:#{vcs.url} should have a source.yml file, but does not"
            end

            source_definition = Autoproj.in_file(source_file, Autoproj::YAML_LOAD_ERROR) do
                YAML.load(File.read(source_file))
            end

            if !source_definition || !source_definition['name']
                raise ConfigError.new(source_file), "in #{source_file}: missing a 'name' field"
            end

            source_definition
        end

        # Load and validate the self-contained information from the YAML hash
        def load_minimal
            # If @source_definition is set, it means that load_description_file
            # has been called and that therefore all information has already
            # been parsed
            definition = @source_definition || raw_description_file
            @name = definition['name']

            if @name !~ /^[\w\.-]+$/
                raise ConfigError.new(source_file),
                    "in #{source_file}: invalid source name '#{@name}': source names can only contain alphanumeric characters, and .-_"
            elsif @name == "local"
                raise ConfigError.new(source_file),
                    "in #{source_file}: the name 'local' is a reserved name"
            end

            @provides = (definition['provides'] || Set.new).to_set
            @imports  = (definition['imports'] || Array.new).map do |set_def|
                pkg_set = Autoproj.in_file(source_file) do
                    PackageSet.from_spec(manifest, set_def, false)
                end

                pkg_set.imported_from = self
                pkg_set
            end

        rescue InternalError
            # This ignores raw_description_file error if the package set is not
            # checked out yet
        end

        # Yields the imports this package set declares, as PackageSet instances
        def each_imported_set(&block)
            @imports.each(&block)
        end

        # Path to the source.yml file
        def source_file
            File.join(local_dir, 'source.yml')
        end

        # Load the source.yml file and resolves all information it contains.
        #
        # This for instance requires configuration options to be defined. Use
        # PackageSet#load_minimal to load only self-contained information
        def load_description_file
            if @source_definition
                return
            end

            @source_definition = raw_description_file
            load_minimal

            # Compute the definition of constants
            Autoproj.in_file(source_file) do
                constants = source_definition['constants'] || Hash.new
                @constants_definitions = Autoproj.resolve_constant_definitions(constants)
            end
        end

        def single_expansion(data, additional_expansions = Hash.new)
            if !source_definition
                load_description_file
            end
            Autoproj.single_expansion(data, additional_expansions.merge(constants_definitions))
        end

        # Expands the given string as much as possible using the expansions
        # listed in the source.yml file, and returns it. Raises if not all
        # variables can be expanded.
        def expand(data, additional_expansions = Hash.new)
            if !source_definition
                load_description_file
            end
            Autoproj.expand(data, additional_expansions.merge(constants_definitions))
        end

        # Returns the default importer definition for this package set, as a
        # VCSDefinition instance
        def default_importer
            importer_definition_for('default')
        end

        # Returns an importer definition for the given package, if one is
        # available. Otherwise returns nil.
        #
        # The returned value is a VCSDefinition object.
        def version_control_field(package_name, section_name, validate = true)
            urls = source_definition['urls'] || Hash.new
            urls['HOME'] = ENV['HOME']

            all_vcs     = source_definition[section_name]
            if all_vcs
                if all_vcs.kind_of?(Hash)
                    raise ConfigError.new, "wrong format for the #{section_name} section, you forgot the '-' in front of the package names"
                elsif !all_vcs.kind_of?(Array)
                    raise ConfigError.new, "wrong format for the #{section_name} section"
                end
            end

            raw = []
            vcs_spec = Hash.new

            if all_vcs
                all_vcs.each do |spec|
                    spec = spec.dup
                    if spec.values.size != 1
                        # Maybe the user wrote the spec like
                        #   - package_name:
                        #     type: git
                        #     url: blah
                        #
                        # or as
                        #   - package_name
                        #     type: git
                        #     url: blah
                        #
                        # In that case, we should have the package name as
                        # "name => nil". Check that.
                        name, _ = spec.find { |n, v| v.nil? }
                        if name
                            spec.delete(name)
                        else
                            name, _ = spec.find { |n, v| n =~ / \w+$/ }
                            name =~ / (\w+)$/
                            spec[$1] = spec.delete(name)
                            name = name.gsub(/ \w+$/, '')
                        end
                    else
                        name, spec = spec.to_a.first
                        if name =~ / (\w+)/
                            spec = { $1 => spec }
                            name = name.gsub(/ \w+$/, '')
                        end

                        if spec.respond_to?(:to_str)
                            if spec == "none"
                                spec = { :type => "none" }
                            else
                                raise ConfigError.new, "invalid VCS specification in the #{section_name} section '#{name}: #{spec}'"
                            end
                        end
                    end

                    name_match = name
                    if name_match =~ /[^\w\/-]/
                        name_match = Regexp.new("^" + name_match)
                    end
                    if name_match === package_name
                        raw << [self.name, spec]
                        vcs_spec =
                            begin
                                VCSDefinition.update_raw_vcs_spec(vcs_spec, spec)
                            rescue ConfigError => e
                                raise ConfigError.new, "invalid VCS definition in the #{section_name} section for '#{name}': #{e.message}", e.backtrace
                            end
                    end
                end
            end

            if !vcs_spec.empty?
                expansions = Hash["PACKAGE" => package_name,
                    "PACKAGE_BASENAME" => File.basename(package_name),
                    "AUTOPROJ_ROOT" => Autoproj.root_dir,
                    "AUTOPROJ_CONFIG" => Autoproj.config_dir,
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
            else
                return nil, []
            end
        end

        # Returns the VCS definition for +package_name+ as defined in this
        # source, or nil if the source does not have any.
        #
        # The definition is an instance of VCSDefinition
        def importer_definition_for(package_name)
            Autoproj.in_file source_file do
                vcs_spec, raw = version_control_field(package_name, 'version_control')
                if vcs_spec
                    VCSDefinition.from_raw(vcs_spec, raw)
                end
            end
        end

        # Enumerates the Autobuild::Package instances that are defined in this
        # source
        def each_package
            if !block_given?
                return enum_for(:each_package)
            end

            Autoproj.manifest.packages.each_value do |pkg|
                if pkg.package_set.name == name
                    yield(pkg.autobuild)
                end
            end
        end

        # True if this package set provides the given package set name. I.e. if
        # it has this name or the name is listed in the "replaces" field of
        # source.yml
        def provides?(name)
            name == self.name ||
                provides.include?(name)
        end
    end

    # Specialization of the PackageSet class for the overrides listed in autoproj/
    class LocalPackageSet < PackageSet
        def initialize(manifest)
            super(manifest, VCSDefinition.from_raw(:type => 'local', :url => Autoproj.config_dir))
        end

        def name
            'local'
        end
        def load_minimal
        end
        def repository_id
            'local'
        end

        def source_file
            File.join(Autoproj.config_dir, "overrides.yml")
        end

        # Returns the default importer for this package set
        def default_importer
            importer_definition_for('default') ||
                VCSDefinition.from_raw(:type => 'none')
        end

        def raw_description_file
            path = source_file
            if File.file?(path)
                data = Autoproj.in_file(path, Autoproj::YAML_LOAD_ERROR) do
                    YAML.load(File.read(path)) || Hash.new
                end
                data['name'] = 'local'
                data
            else
                { 'name' => 'local' }
            end
        end
    end

    # DEPRECATED. For backward-compatibility only.
    Source = PackageSet
    # DEPRECATED. For backward-compatibility only.
    LocalSource = LocalPackageSet
end
