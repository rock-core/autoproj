require 'yaml'
require 'utilrb/kernel/options'
require 'nokogiri'
require 'set'

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

    # Expand build options in +value+.
    #
    # The method will expand in +value+ patterns of the form $NAME, replacing
    # them with the corresponding build option.
    def self.expand_environment(value)
        # Perform constant expansion on the defined environment variables,
        # including the option set
        options = Autoproj.option_set
        options.each_key do |k|
            options[k] = options[k].to_s
        end

        loop do
            new_value = Autoproj.single_expansion(value, options)
            if new_value == value
                break
            else
                value = new_value
            end
        end
        value
    end

    @env_inherit = Set.new
    # Returns true if the given environment variable must not be reset by the
    # env.sh script, but that new values should simply be prepended to it.
    #
    # See Autoproj.env_inherit
    def self.env_inherit?(name)
        @env_inherit.include?(name)
    end
    # Declare that the given environment variable must not be reset by the
    # env.sh script, but that new values should simply be prepended to it.
    #
    # See Autoproj.env_inherit?
    def self.env_inherit(*names)
        @env_inherit |= names
    end

    # Resets the value of the given environment variable to the given
    def self.env_set(name, *value)
        Autobuild.env_clear(name)
        env_add(name, *value)
    end
    def self.env_add(name, *value)
        value = value.map { |v| expand_environment(v) }
        Autobuild.env_add(name, *value)
    end
    def self.env_set_path(name, *value)
        Autobuild.env_clear(name)
        env_add_path(name, *value)
    end
    def self.env_add_path(name, *value)
        value = value.map { |v| expand_environment(v) }
        Autobuild.env_add_path(name, *value)
    end

    class VCSDefinition
        attr_reader :type
        attr_reader :url
        attr_reader :options

        def initialize(type, url, options)
            @type, @url, @options = type, url, options
            if type != "none" && type != "local" && !Autobuild.respond_to?(type)
                raise ConfigError.new, "version control #{type} is unknown to autoproj"
            end
        end

        def local?
            @type == 'local'
        end

        def ==(other_vcs)
            return false if !other_vcs.kind_of?(VCSDefinition)
            if local?
                other_vcs.local? && url == other.url
            elsif !other_vcs.local?
                this_importer = create_autobuild_importer
                other_importer = other_vcs.create_autobuild_importer
                this_importer.repository_id == other_importer.repository_id
            end
        end

        def self.to_absolute_url(url, root_dir = nil)
            # NOTE: we MUST use nil as default argument of root_dir as we don't
            # want to call Autoproj.root_dir unless completely necessary
            # (to_absolute_url might be called on installations that are being
            # bootstrapped, and as such don't have a root dir yet).
            url = Autoproj.single_expansion(url, 'HOME' => ENV['HOME'])
            if url && url !~ /^(\w+:\/)?\/|^\w+\@|^(\w+\@)?[\w\.-]+:/
                url = File.expand_path(url, root_dir || Autoproj.root_dir)
            end
            url
        end

        def create_autobuild_importer
            return if type == "none"

            url = VCSDefinition.to_absolute_url(self.url)
            Autobuild.send(type, url, options)
        end

        def to_s 
            if type == "none"
                "none"
            else
                desc = "#{type}:#{url}"
                if !options.empty?
                    desc = "#{desc} #{options.to_a.sort_by { |key, _| key.to_s }.map { |key, value| "#{key}=#{value}" }.join(" ")}"
                end
                desc
            end
        end
    end

    def self.vcs_definition_to_hash(spec)
        options = Hash.new
        if spec.size == 1 && spec.keys.first =~ /auto_imports$/
            # The user probably wrote
            #   - string
            #     auto_imports: false
            options['auto_imports'] = spec.values.first
            spec = spec.keys.first.split(" ").first
        end

        if spec.respond_to?(:to_str)
            vcs, *url = spec.to_str.split ':'
            spec = if url.empty?
                       source_dir = File.expand_path(File.join(Autoproj.config_dir, spec))
                       if !File.directory?(source_dir)
                           raise ConfigError.new, "'#{spec.inspect}' is neither a remote source specification, nor a local source definition"
                       end

                       Hash[:type => 'local', :url => source_dir]
                   else
                       Hash[:type => vcs.to_str, :url => url.join(":").to_str]
                   end
        end

        spec, vcs_options = Kernel.filter_options spec, :type => nil, :url => nil

        return spec.merge(vcs_options).merge(options)
    end

    # Autoproj configuration files accept VCS definitions in three forms:
    #  * as a plain string, which is a relative/absolute path
    #  * as a plain string, which is a vcs_type:url string
    #  * as a hash
    #
    # This method normalizes the three forms into a VCSDefinition object
    def self.normalize_vcs_definition(spec)
        spec = vcs_definition_to_hash(spec)
        if !(spec[:type] && (spec[:type] == 'none' || spec[:url]))
            raise ConfigError.new, "the source specification #{spec.inspect} misses either the VCS type or an URL"
        end

        spec, vcs_options = Kernel.filter_options spec, :type => nil, :url => nil
        return VCSDefinition.new(spec[:type], spec[:url], vcs_options)
    end

    def self.single_expansion(data, definitions)
        if !data.respond_to?(:to_str)
            return data
        end
        definitions = { 'HOME' => ENV['HOME'] }.merge(definitions)

        data = data.gsub /\$(\w+)/ do |constant_name|
            constant_name = constant_name[1..-1]
            if !(value = definitions[constant_name])
                if !(value = Autoproj.user_config(constant_name))
                    if !block_given? || !(value = yield(constant_name))
                        raise ArgumentError, "cannot find a definition for $#{constant_name}"
                    end
                end
            end
            value
        end
        data
    end

    def self.expand(value, definitions = Hash.new)
        if value.respond_to?(:to_hash)
            value.dup.each do |name, definition|
                value[name] = expand(definition, definitions)
            end
            value
        else
            value = single_expansion(value, definitions)
            if contains_expansion?(value)
                raise ConfigError.new, "some expansions are not defined in #{value.inspect}"
            end
            value
        end
    end

    # True if the given string contains expansions
    def self.contains_expansion?(string); string =~ /\$/ end

    def self.resolve_one_constant(name, value, result, definitions)
        result[name] = single_expansion(value, result) do |missing_name|
            result[missing_name] = resolve_one_constant(missing_name, definitions.delete(missing_name), result, definitions)
        end
    end

    def self.resolve_constant_definitions(constants)
        constants = constants.dup
        constants['HOME'] = ENV['HOME']
        
        result = Hash.new
        while !constants.empty?
            name  = constants.keys.first
            value = constants.delete(name)
            resolve_one_constant(name, value, result, constants)
        end
        result
    end

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

        # Create a PackageSet instance from its description as found in YAML
        # configuration files
        def self.from_spec(manifest, spec, load_description)
            spec = Autoproj.vcs_definition_to_hash(spec)
            options, vcs_spec = Kernel.filter_options spec, :auto_imports => true

            # Look up for short notation (i.e. not an explicit hash). It is
            # either vcs_type:url or just url. In the latter case, we expect
            # 'url' to be a path to a local directory
            vcs_spec = Autoproj.expand(vcs_spec, manifest.constant_definitions)
            vcs_def  = Autoproj.normalize_vcs_definition(vcs_spec)

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
                File.expand_path(File.join(Autoproj.remotes_dir, vcs.to_s.gsub(/[^\w]/, '_')))
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

            source_definition = Autoproj.in_file(source_file, ArgumentError) do
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

            if @name !~ /^[\w_\.-]+$/
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
                                raise ConfigError.new, "invalid VCS specification '#{name}: #{spec}'"
                            end
                        end
                    end

                    if Regexp.new("^" + name) =~ package_name
                        vcs_spec = vcs_spec.merge(spec)
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
                vcs_spec = Autoproj.vcs_definition_to_hash(vcs_spec)
                vcs_spec.dup.each do |name, value|
                    vcs_spec[name] = expand(value, expansions)
                end

                # If required, verify that the configuration is a valid VCS
                # configuration
                if validate
                    Autoproj.normalize_vcs_definition(vcs_spec)
                end
                vcs_spec
            end
        end

        # Returns the VCS definition for +package_name+ as defined in this
        # source, or nil if the source does not have any.
        #
        # The definition is an instance of VCSDefinition
        def importer_definition_for(package_name)
            vcs_spec = version_control_field(package_name, 'version_control')
            if vcs_spec
                Autoproj.normalize_vcs_definition(vcs_spec)
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
            super(manifest, Autoproj.normalize_vcs_definition(:type => 'local', :url => Autoproj.config_dir))
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
                Autoproj.normalize_vcs_definition(:type => 'none')
        end

        def raw_description_file
            path = source_file
            if File.file?(path)
                data = Autoproj.in_file(path, ArgumentError) do
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

    PackageDefinition = Struct.new :autobuild, :user_block, :package_set, :file

    # The Manifest class represents the information included in the main
    # manifest file, and allows to manipulate it
    class Manifest

        # Data structure used to use autobuild importers without a package, to
        # import configuration data.
        #
        # It has to match the interface of Autobuild::Package that is relevant
        # for importers
        class FakePackage
            attr_reader :text_name
            attr_reader :name
            attr_reader :srcdir
            attr_reader :importer

            # Used by the autobuild importers
            attr_accessor :updated

            def initialize(text_name, srcdir, importer = nil)
                @text_name = text_name
                @name = text_name.gsub /[^\w]/, '_'
                @srcdir = srcdir
                @importer = importer
            end

            def import
                importer.import(self)
            end

            def progress(msg)
                Autobuild.progress(msg % [text_name])
            end

            # Display a progress message, and later on update it with a progress
            # value. %s in the string is replaced by the package name
            def progress_with_value(msg)
                Autobuild.progress_with_value(msg % [text_name])
            end

            def progress_value(value)
                Autobuild.progress_value(value)
            end
        end

        # The set of packages that are selected by the user, either through the
        # manifest file or through the command line, as a set of package names
        attr_accessor :explicit_selection

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
                raise ConfigError.new(dirname), "expected an autoproj configuration in #{dirname}, but #{file} does not exist"
            end

            data = Autoproj.in_file(file, ArgumentError) do
                YAML.load(File.read(file))
            end

            @file = file
            @data = data

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

        # True if osdeps should be handled in update and build, or left to the
        # osdeps command
        def auto_osdeps?
            if data.has_key?('auto_osdeps')
                !!data['auto_osdeps']
            else true
            end
        end

        # True if autoproj should run an update automatically when the user
        # uses" build"
        def auto_update?
            !!data['auto_update']
        end

        attr_reader :constant_definitions

	def initialize
            @file = nil
	    @data = nil
            @packages = Hash.new
            @package_manifests = Hash.new
            @automatic_exclusions = Hash.new
            @constants_definitions = Hash.new
            @disabled_imports = Set.new
            @moved_packages = Hash.new

            @constant_definitions = Hash.new
            if Autoproj.has_config_key?('manifest_source')
                @vcs = Autoproj.normalize_vcs_definition(Autoproj.user_config('manifest_source'))
            end
	end

        # True if the given package should not be built, with the packages that
        # depend on him have this dependency met.
        #
        # This is useful if the packages are already installed on this system.
        def ignored?(package_name)
            if data['ignore_packages']
                data['ignore_packages'].any? { |l| Regexp.new(l) =~ package_name }
            else
                false
            end
        end

        # The set of package names that are listed in the excluded_packages
        # section of the manifest
        def manifest_exclusions
            data['exclude_packages'] || Set.new
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
        # excluded_packages section of the manifest, or because they are
        # disabled on this particular operating system.
        def exclusion_reason(package_name)
            if manifest_exclusions.any? { |l| Regexp.new(l) =~ package_name }
                "#{package_name} is listed in the excluded_packages section of the manifest"
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
                return enum_for(:each_source_file, source_name)
            end

            # This looks very inefficient, but it is because source names are
            # contained in source.yml and we must therefore load that file to
            # check the package set name ...
            #
            # And honestly I don't think someone will have 20 000 package sets
            done_something = false
            each_source(false) do |source| 
                next if source_name && source.name != source_name
                done_something = true

                Dir.glob(File.join(source.local_dir, "*.autobuild")).each do |file|
                    yield(source, file)
                end
            end

            if source_name && !done_something
                raise ConfigError.new(file), "in #{file}: source '#{source_name}' does not exist"
            end
	end

        # Yields each osdeps definition files that are present in our sources
        def each_osdeps_file
            if !block_given?
                return enum_for(:each_source_file)
            end

            each_source(false) do |source|
		Dir.glob(File.join(source.local_dir, "*.osdeps")).each do |file|
		    yield(source, file)
		end
            end
        end

        # True if some of the sources are remote sources
        def has_remote_sources?
            each_remote_source(false).any? { true }
        end

        # True if calling update_remote_sources will actually do anything
        def should_update_remote_sources
            if Autobuild.do_update
                return true
            end

            each_remote_source(false) do |source|
                if !File.directory?(source.local_dir)
                    return true
                end
            end
            false
        end

        # Like #each_source, but filters out local package sets
        def each_remote_package_set(load_description = true)
            if !block_given?
                enum_for(:each_remote_package_set, load_description)
            else
                each_package_set(load_description) do |source|
                    if !source.local?
                        yield(source)
                    end
                end
            end
        end

        def each_remote_source(*args, &block)
            each_remote_package_set(*args, &block)
        end

        # Helper method for #each_package_set
        def enumerate_package_set(pkg_set, explicit_sets, all_sets) # :nodoc:
            if @disabled_imports.include?(pkg_set.name)
                pkg_set.auto_imports = false
            end

            result = []
            if pkg_set.auto_imports?
                pkg_set.each_imported_set do |imported_set|
                    if explicit_sets.any? { |src| src.vcs == imported_set.vcs } ||
                        all_sets.any? { |src| src.vcs == imported_set.vcs }
                        next
                    end

                    all_sets << imported_set
                    result.concat(enumerate_package_set(imported_set, explicit_sets, all_sets))
                end
            end
            result << pkg_set
            result
        end

        # call-seq:
        #   each_package_set { |pkg_set| ... }
        #
        # Lists all package sets defined in this manifest, by yielding a
        # PackageSet object that describes it.
        def each_package_set(load_description = true, &block)
            if !block_given?
                return enum_for(:each_package_set, load_description)
            end

            if @package_sets
                if load_description
                    @package_sets.each do |src|
                        if !src.source_definition
                            src.load_description_file
                        end
                    end
                end
                return @package_sets.each(&block)
            end

	    explicit_sets = (data['package_sets'] || []).map do |spec|
                Autoproj.in_file(self.file) do
                    PackageSet.from_spec(self, spec, load_description)
                end
            end

            all_sets = Array.new
            explicit_sets.each do |pkg_set|
                all_sets.concat(enumerate_package_set(pkg_set, explicit_sets, all_sets + [pkg_set]))
            end

            # Now load the local source 
            local = LocalPackageSet.new(self)
            if load_description
                local.load_description_file
            else
                local.load_minimal
            end
            if !load_description || !local.empty?
                all_sets << local
            end
            
            if load_description
                all_sets.each(&:load_description_file)
            else
                all_sets.each(&:load_minimal)
            end
            all_sets.each(&block)
        end

        # DEPRECATED. For backward-compatibility only
        #
        # use #each_package_set instead
        def each_source(*args, &block)
            each_package_set(*args, &block)
        end

        def local_package_set
            each_package_set.find { |s| s.kind_of?(LocalPackageSet) }
        end

        # Save the currently known package sets. After this call,
        # #each_package_set will always return the same set regardless of
        # changes on the manifest's data structures
        def cache_package_sets
            @package_sets = each_package_set(false).to_a
        end

        # Register a new package
        def register_package(package, block, source, file)
            @packages[package.name] = PackageDefinition.new(package, block, source, file)
        end

        def definition_source(package_name)
            @packages[package_name].package_set
        end
        def definition_file(package_name)
            @packages[package_name].file
        end

        def package(name)
            packages[name]
        end

        # Lists all defined packages and where they have been defined
        def each_package
            if !block_given?
                return enum_for(:each_package)
            end
            packages.each_value { |pkg| yield(pkg.autobuild) }
        end

        # The VCS object for the main configuration itself
        attr_reader :vcs

        def each_configuration_source
            if !block_given?
                return enum_for(:each_configuration_source)
            end

            if vcs
                yield(vcs, "autoproj main configuration", Autoproj.config_dir)
            end

            each_remote_source(false) do |source|
                yield(source.vcs, source.name || source.vcs.url, source.local_dir)
            end
            self
        end

        # Creates an autobuild package whose job is to allow the import of a
        # specific repository into a given directory.
        #
        # +vcs+ is the VCSDefinition file describing the repository, +text_name+
        # the name used when displaying the import progress, +pkg_name+ the
        # internal name used to represent the package and +into+ the directory
        # in which the package should be checked out.
        def self.create_autobuild_package(vcs, text_name, into)
            importer     = vcs.create_autobuild_importer
            return if !importer # updates have been disabled by using the 'none' type

            FakePackage.new(text_name, into, importer)

        rescue Autobuild::ConfigException => e
            raise ConfigError.new, "cannot import #{name}: #{e.message}", e.backtrace
        end

        # Imports or updates a source (remote or otherwise).
        #
        # See create_autobuild_package for informations about the arguments.
        def self.update_package_set(vcs, text_name, into)
            fake_package = create_autobuild_package(vcs, text_name, into)
            fake_package.import

        rescue Autobuild::ConfigException => e
            raise ConfigError.new, "cannot import #{name}: #{e.message}", e.backtrace
        end

        # Updates the main autoproj configuration
        def update_yourself
            Manifest.update_package_set(vcs, "autoproj main configuration", Autoproj.config_dir)
        end

        def update_remote_set(pkg_set, remotes_symlinks_dir = nil)
            Manifest.update_package_set(
                pkg_set.vcs,
                pkg_set.name,
                pkg_set.raw_local_dir)

            if remotes_symlinks_dir
                pkg_set.load_minimal
                symlink_dest = File.join(remotes_symlinks_dir, pkg_set.name)

                # Check if the current symlink is valid, and recreate it if it
                # is not
                if File.symlink?(symlink_dest)
                    dest = File.readlink(symlink_dest)
                    if dest != pkg_set.raw_local_dir
                        FileUtils.rm_f symlink_dest
                        FileUtils.ln_sf pkg_set.raw_local_dir, symlink_dest
                    end
                else
                    FileUtils.rm_f symlink_dest
                    FileUtils.ln_sf pkg_set.raw_local_dir, symlink_dest
                end

                symlink_dest
            end
        end

        # Updates all the remote sources in ROOT_DIR/.remotes, as well as the
        # symbolic links in ROOT_DIR/autoproj/remotes
        def update_remote_package_sets
            remotes_symlinks_dir = File.join(Autoproj.config_dir, 'remotes')
            FileUtils.mkdir_p remotes_symlinks_dir

            # Iterate on the remote sources, without loading the source.yml
            # file (we're not ready for that yet)
            #
            # Do it iteratively to properly take imports into account, but we
            # first unconditionally update all the existing sets to properly
            # handle imports that have been removed
            updated_sets     = Hash.new
            known_remotes = []
            each_remote_package_set(false) do |pkg_set|
                next if !pkg_set.explicit?
                if pkg_set.present?
                    known_remotes << update_remote_set(pkg_set, remotes_symlinks_dir)
                    updated_sets[pkg_set.repository_id] = pkg_set
                end
            end

            old_updated_sets = nil
            while old_updated_sets != updated_sets
                old_updated_sets = updated_sets.dup
                each_remote_package_set(false) do |pkg_set|
                    next if updated_sets.has_key?(pkg_set.repository_id)

                    if !pkg_set.explicit?
                        Autoproj.progress "  #{pkg_set.imported_from.name}: auto-importing #{pkg_set.name}"
                    end
                    known_remotes << update_remote_set(pkg_set, remotes_symlinks_dir)
                    updated_sets[pkg_set.repository_id] = pkg_set
                end
            end

            # Check for directories in ROOT_DIR/.remotes that do not map to a
            # source repository, and remove them
            Dir.glob(File.join(Autoproj.remotes_dir, '*')).each do |dir|
                dir = File.expand_path(dir)
                if File.directory?(dir) && !updated_sets.values.find { |pkg| pkg.raw_local_dir == dir }
                    FileUtils.rm_rf dir
                end
            end

            # Now remove obsolete symlinks
            Dir.glob(File.join(remotes_symlinks_dir, '*')).each do |file|
                if File.symlink?(file) && !known_remotes.include?(file)
                    FileUtils.rm_f file
                end
            end
        end

        # DEPRECATED. For backward-compatibility only
        def update_remote_sources(*args, &block)
            update_remote_package_sets(*args, &block)
        end

        def importer_definition_for(package_name, package_source = nil)
            if !package_source
                package_source = packages.values.
                    find { |pkg| pkg.autobuild.name == package_name }.
                    package_set
            end

            sources = each_source.to_a.dup

            # Remove sources listed before the package source
            while !sources.empty? && sources[0].name != package_source.name
                sources.shift
            end
            package_source = sources.shift
            if !package_source
                raise InternalError, "cannot find the package set that defines #{package_name}"
            end

            # Get the version control information from the package source. There
            # must be one
            vcs_spec = package_source.version_control_field(package_name, 'version_control')
            return if !vcs_spec

            sources.each do |src|
                overrides_spec = src.version_control_field(package_name, 'overrides', false)
                if overrides_spec
                    vcs_spec.merge!(overrides_spec)
                end
            end
            Autoproj.normalize_vcs_definition(vcs_spec)
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
                    pkg.autobuild.importer = vcs.create_autobuild_importer
                else
                    raise ConfigError.new, "source #{pkg.package_set.name} defines #{pkg.autobuild.name}, but does not provide a version control definition for it"
                end
            end
        end

        # Returns true if +name+ is the name of a package set known to this
        # autoproj installation
        def has_package_set?(name)
            each_package_set(false).find { |set| set.name == name }
        end

        # +name+ can either be the name of a source or the name of a package. In
        # the first case, we return all packages defined by that source. In the
        # latter case, we return the singleton array [name]
        def resolve_package_set(name)
            if Autobuild::Package[name]
                [name]
            else
                pkg_set = each_package_set(false).find { |set| set.name == name }
                if !pkg_set
                    raise ConfigError.new, "#{name} is neither a package nor a source"
                end
                packages.values.
                    find_all { |pkg| pkg.package_set.name == pkg_set.name }.
                    map { |pkg| pkg.autobuild.name }.
                    find_all { |pkg_name| !Autoproj.osdeps || !Autoproj.osdeps.has?(pkg_name) }
            end
        end

        # Returns the packages contained in the provided layout definition
        #
        # If recursive is false, yields only the packages at this level.
        # Otherwise, return all packages.
        def layout_packages(result, validate)
            normalized_layout.each_key do |pkg_or_set|
                begin
                    resolve_package_set(pkg_or_set).each do |pkg_name|
                        result << pkg_name
                        Autobuild::Package[pkg_name].all_dependencies(result)
                    end
                rescue ConfigError
                    raise if validate
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
            packages.values.
                map { |pkg| pkg.autobuild.name }.
                find_all { |pkg_name| !Autoproj.osdeps || !Autoproj.osdeps.has?(pkg_name) }
        end

        # Returns true if +name+ is a valid package and is included in the build
        #
        # If +validate+ is true, the method will raise ArgumentError if the
        # package does not exists. 
        #
        # If it is false, the method will simply return false on non-defined
        # packages 
        def package_enabled?(name, validate = true)
            if !Autobuild::Package[name]
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
        def all_selected_packages
            result = default_packages.to_set
            result.each do |pkg_name|
                Autobuild::Package[pkg_name].all_dependencies(result)
            end
            result
        end

        # Returns the set of packages that should be built if the user does not
        # specify any on the command line
        def default_packages(validate = true)
            names = if layout = data['layout']
                        layout_packages(Set.new, validate)
                    else
                        # No layout, all packages are selected
                        all_packages
                    end

            names.delete_if { |pkg_name| excluded?(pkg_name) || ignored?(pkg_name) }
            names.to_set
        end

        def normalized_layout(result = Hash.new { '/' }, layout_level = '/', layout_data = (data['layout'] || Hash.new))
            layout_data.each do |value|
                if value.kind_of?(Hash)
                    subname, subdef = value.find { true }
                    normalized_layout(result, "#{layout_level}#{subname}/", subdef)
                else
                    result[value] = layout_level
                end
            end
            result
        end

        # Returns the package directory for the given package name
        def whereis(package_name)
            Autoproj.in_file(self.file) do
                set_name = definition_source(package_name).name
                actual_layout = normalized_layout
                return actual_layout[package_name] || actual_layout[set_name]
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
            package, source, file = pkg.autobuild, pkg.package_set, pkg.file

            if !pkg_name
                raise ArgumentError, "package #{pkg_name} is not defined"
            end

            manifest_path = File.join(package.srcdir, "manifest.xml")
            if !File.file?(manifest_path)
                Autoproj.warn "#{package.name} from #{source.name} does not have a manifest"
                return
            end

            manifest = PackageManifest.load(package, manifest_path)
            package_manifests[package.name] = manifest

            manifest.each_dependency do |name, is_optional|
                begin
                    if is_optional
                        package.optional_dependency name
                    else
                        package.depends_on name
                    end
                rescue Autobuild::ConfigException => e
                    raise ConfigError.new(manifest_path),
                        "manifest #{manifest_path} of #{package.name} from #{source.name} lists '#{name}' as dependency, which is listed in the layout of #{file} but has no autobuild definition", e.backtrace
                rescue ConfigError => e
                    raise ConfigError.new(manifest_path),
                        "manifest #{manifest_path} of #{package.name} from #{source.name} lists '#{name}' as dependency, but it is neither a normal package nor an osdeps package. osdeps reports: #{e.message}", e.backtrace
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

        # Installs the OS dependencies that are required by the given packages
        def install_os_dependencies(packages)
            required_os_packages, package_os_deps = list_os_dependencies(packages)
            Autoproj.osdeps.install(required_os_packages, package_os_deps)
        end

        # Package selection can be done in three ways:
        #  * as a subdirectory in the layout
        #  * as a on-disk directory
        #  * as a package name
        #
        # This method converts the first two directories into the third one
        def expand_package_selection(selection)
            base_dir = Autoproj.root_dir

            # The expanded selection
            expanded_packages = Set.new
            # All the packages that are available on this installation
            all_layout_packages = self.all_selected_packages

            # First, remove packages that are directly referenced by name or by
            # package set names
            selection.each do |sel|
                sel = Regexp.new(Regexp.quote(sel))

                packages = all_layout_packages.
                    find_all { |pkg_name| pkg_name =~ sel }.
                    to_set
                expanded_packages |= packages

                sources = each_source.find_all { |source| source.name =~ sel }
                sources.each do |source|
                    packages = resolve_package_set(source.name).to_set
                    expanded_packages |= (packages & all_layout_packages)
                end

                !packages.empty? || !sources.empty?
            end

            # Finally, check for package source directories
            all_packages = self.all_package_names
            selection.each do |sel|
                match_pkg_name = Regexp.new(Regexp.quote(sel))
                all_packages.each do |pkg_name|
                    pkg = Autobuild::Package[pkg_name]
                    if pkg_name =~ match_pkg_name || sel =~ Regexp.new("^#{Regexp.quote(pkg.srcdir)}") || pkg.srcdir =~ Regexp.new("^#{Regexp.quote(sel)}")
                        # Check-out packages that are not in the manifest only
                        # if they are explicitely selected
                        if pkg_name != sel && pkg.srcdir != sel && !all_layout_packages.include?(pkg.name)
                            next
                        end

                        expanded_packages << pkg_name
                    end
                end
            end

            # Remove packages that are explicitely excluded and/or ignored
            expanded_packages.delete_if { |pkg_name| excluded?(pkg_name) || ignored?(pkg_name) }
            expanded_packages.to_set
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
    end

    class << self
        # The singleton manifest object on which the current run works
        attr_accessor :manifest

        # The operating system package definitions
        attr_accessor :osdeps
    end

    def self.load_osdeps_from_package_sets
        manifest.each_osdeps_file do |source, file|
            osdeps.merge(source.load_osdeps(file))
        end
        osdeps
    end

    class PackageManifest
        def self.load(package, file)
            doc = Nokogiri::XML(File.read(file)) do |c|
                c.noblanks
            end
            PackageManifest.new(package, doc)
        end

        # The Autobuild::Package instance this manifest applies on
        attr_reader :package
        # The raw XML data as a Nokogiri document
        attr_reader :xml

        def short_documentation
            xml.xpath('//description').each do |node|
                if doc = node['brief']
                    return doc.to_s
                end
            end
            nil
        end

        def initialize(package, doc)
            @package = package
            @xml = doc
        end

        def each_dependency(&block)
            if block_given?
                each_os_dependency(&block)
                each_package_dependency(&block)
            else
                enum_for(:each_dependency, &block)
            end
        end

        def each_os_dependency
            if block_given?
                xml.xpath('//rosdep').each do |node|
                    yield(node['name'], false)
                end
                package.os_packages.each do |name|
                    yield(name, false)
                end
            else
                enum_for :each_os_dependency
            end
        end

        def each_package_dependency
            if block_given?
                xml.xpath('//depend').each do |node|
                    dependency = node['package']
                    optional   =
                        if node['optional'].to_s == '1'
                            true
                        else false
                        end

                    if dependency
                        yield(dependency, optional)
                    else
                        raise ConfigError.new, "manifest of #{package.name} has a <depend> tag without a 'package' attribute"
                    end
                end
            else
                enum_for :each_package_dependency
            end
        end
    end
end

