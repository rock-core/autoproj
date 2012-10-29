require 'yaml'
require 'utilrb/kernel/options'
require 'set'
require 'rexml/document'

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

    # Sets an environment variable
    #
    # This sets (or resets) the environment variable +name+ to the given value.
    # If multiple values are given, they are joined with ':'
    #
    # The values can contain configuration parameters using the
    # $CONF_VARIABLE_NAME syntax.
    def self.env_set(name, *value)
        Autobuild.env_clear(name)
        env_add(name, *value)
    end

    # Adds new values to a given environment variable
    #
    # Adds the given value(s) to the environment variable named +name+. The
    # values are added using the ':' marker.
    #
    # The values can contain configuration parameters using the
    # $CONF_VARIABLE_NAME syntax.
    def self.env_add(name, *value)
        value = value.map { |v| expand_environment(v) }
        Autobuild.env_add(name, *value)
    end

    # Sets an environment variable which is a path search variable (such as
    # PATH, RUBYLIB, PYTHONPATH)
    #
    # This sets (or resets) the environment variable +name+ to the given value.
    # If multiple values are given, they are joined with ':'. Unlike env_set,
    # duplicate values will be removed.
    #
    # The values can contain configuration parameters using the
    # $CONF_VARIABLE_NAME syntax.
    def self.env_set_path(name, *value)
        Autobuild.env_clear(name)
        env_add_path(name, *value)
    end

    # Adds new values to a given environment variable, which is a path search
    # variable (such as PATH, RUBYLIB, PYTHONPATH)
    #
    # Adds the given value(s) to the environment variable named +name+. The
    # values are added using the ':' marker. Unlike env_set, duplicate values
    # will be removed.
    #
    # The values can contain configuration parameters using the
    # $CONF_VARIABLE_NAME syntax.
    #
    # This is usually used in package configuration blocks to add paths
    # dependent on the place of install, such as
    #
    #   cmake_package 'test' do |pkg|
    #     Autoproj.env_add_path 'RUBYLIB', File.join(pkg.srcdir, 'bindings', 'ruby')
    #   end
    def self.env_add_path(name, *value)
        value = value.map { |v| expand_environment(v) }
        Autobuild.env_add_path(name, *value)
    end

    # Requests that autoproj source the given shell script in its own env.sh
    # script
    def self.env_source_file(file)
        Autobuild.env_source_file(file)
    end

    # Requests that autoproj source the given shell script in its own env.sh
    # script
    def self.env_source_after(file)
        Autobuild.env_source_after(file)
    end

    # Requests that autoproj source the given shell script in its own env.sh
    # script
    def self.env_source_before(file)
        Autobuild.env_source_before(file)
    end

    # Representation of a VCS definition contained in a source.yml file or in
    # autoproj/manifest
    class VCSDefinition
        attr_reader :type
        attr_reader :url
        attr_reader :options

        # The original spec in hash form. Set if this VCSDefinition object has
        # been created using VCSDefinition.from_raw
        attr_reader :raw

        def initialize(type, url, options, raw = nil)
            if raw && !raw.respond_to?(:to_ary)
                raise ArgumentError, "wrong format for the raw field (#{raw.inspect})"
            end

            @type, @url, @options = type, url, options
            if type != "none" && type != "local" && !Autobuild.respond_to?(type)
                raise ConfigError.new, "version control #{type} is unknown to autoproj"
            end
            @raw = raw
        end

        def local?
            @type == 'local'
        end

        # Updates the VCS specification +old+ by the information contained in
        # +new+
        #
        # Both +old+ and +new+ are supposed to be in hash form. It is assumed
        # that +old+ has already been normalized by a call to
        # Autoproj.vcs_definition_to_hash. +new+ can be in "raw" form.
        def self.update_raw_vcs_spec(old, new)
            new = vcs_definition_to_hash(new)
            if new.has_key?(:type) && (old[:type] != new[:type])
                # The type changed. We replace the old definition by the new one
                # completely, and we make sure that the new definition is valid
                from_raw(new)
                new
            else
                old.merge(new)
            end
        end

        # Normalizes a VCS definition contained in a YAML file into a hash
        #
        # It handles custom source handler expansion, as well as the bad habit
        # of forgetting a ':' at the end of a line:
        #
        #   - package_name
        #     branch: value
        def self.vcs_definition_to_hash(spec)
            options = Hash.new

            plain = Array.new
            filtered_spec = Hash.new
            spec.each do |key, value|
                keys = key.to_s.split(/\s+/)
                plain.concat(keys[0..-2])
                filtered_spec[keys[-1].to_sym] = value
            end
            spec = filtered_spec

            if plain.size > 1
                raise ConfigError.new, "invalid syntax"
            elsif plain.size == 1
                short_url = plain.first
                vcs, *url = short_url.split(':')

                # Check if VCS is a known version control system or source handler
                # shortcut. If it is not, look for a local directory called
                # short_url
                if Autobuild.respond_to?(vcs)
                    spec.merge!(:type => vcs, :url => url.join(':'))
                elsif Autoproj.has_source_handler?(vcs)
                    spec = Autoproj.call_source_handler(vcs, url.join(':'), spec)
                else
                    source_dir = File.expand_path(File.join(Autoproj.config_dir, short_url))
                    if !File.directory?(source_dir)
                        raise ConfigError.new, "'#{spec.inspect}' is neither a remote source specification, nor a local source definition"
                    end
                    spec.merge!(:type => 'local', :url => source_dir)
                end
            end

            spec, vcs_options = Kernel.filter_options spec, :type => nil, :url => nil
            spec.merge!(vcs_options)
            if !spec[:url]
                # Verify that none of the keys are source handlers. If it is the
                # case, convert
                filtered_spec = Hash.new
                spec.dup.each do |key, value|
                    if Autoproj.has_source_handler?(key)
                        spec.delete(key)
                        spec = Autoproj.call_source_handler(key, value, spec)
                        break
                    end
                end
            end

            spec
        end

        # Autoproj configuration files accept VCS definitions in three forms:
        #  * as a plain string, which is a relative/absolute path
        #  * as a plain string, which is a vcs_type:url string
        #  * as a hash
        #
        # This method returns the VCSDefinition object matching one of these
        # specs. It raises ConfigError if there is no type and/or url
        def self.from_raw(spec, raw_spec = [[nil, spec]])
            spec = vcs_definition_to_hash(spec)
            if !(spec[:type] && (spec[:type] == 'none' || spec[:url]))
                raise ConfigError.new, "the source specification #{spec.inspect} misses either the VCS type or an URL"
            end

            spec, vcs_options = Kernel.filter_options spec, :type => nil, :url => nil
            return VCSDefinition.new(spec[:type], spec[:url], vcs_options, raw_spec)
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
            if url && url !~ /^(\w+:\/)?\/|^[:\w]+\@|^(\w+\@)?[\w\.-]+:/
                url = File.expand_path(url, root_dir || Autoproj.root_dir)
            end
            url
        end

        # Returns a properly configured instance of a subclass of
        # Autobuild::Importer that match this VCS definition
        #
        # Returns nil if the VCS type is 'none'
        def create_autobuild_importer
            return if type == "none"

            url = VCSDefinition.to_absolute_url(self.url)
            Autobuild.send(type, url, options)
        end

        # Returns a pretty representation of this VCS definition
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

    @custom_source_handlers = Hash.new

    # Returns true if +vcs+ refers to a source handler name added by
    # #add_source_handler
    def self.has_source_handler?(vcs)
        @custom_source_handlers.has_key?(vcs.to_s)
    end

    # Returns the source handlers associated with +vcs+
    #
    # Source handlers are added by Autoproj.add_source_handler. The returned
    # value is an object that responds to #call(url, options) and return a VCS
    # definition as a hash
    def self.call_source_handler(vcs, url, options)
        handler = @custom_source_handlers[vcs.to_s]
        if !handler
            raise ArgumentError, "there is no source handler for #{vcs}"
        else
            return handler.call(url, options)
        end
    end

    # call-seq:
    #   Autoproj.add_source_handler name do |url, options|
    #     # build a hash that represent source configuration
    #     # and return it
    #   end
    #
    # Add a custom source handler named +name+
    #
    # Custom source handlers are shortcuts that can be used to represent VCS
    # information. For instance, the gitorious_server_configuration method
    # defines a source handler that allows to easily add new gitorious packages:
    #
    #   gitorious_server_configuration 'GITORIOUS', 'gitorious.org'
    #
    # defines the "gitorious" source handler, which allows people to write
    #
    #
    #   version_control:
    #       - tools/orocos.rb
    #         gitorious: rock-toolchain/orocos-rb
    #         branch: test
    #
    # 
    def self.add_source_handler(name, &handler)
        @custom_source_handlers[name.to_s] = lambda(&handler)
    end

    # Does a non-recursive expansion in +data+ of configuration variables
    # ($VAR_NAME) listed in +definitions+
    #
    # If the values listed in +definitions+ also contain configuration
    # variables, they do not get expanded
    def self.single_expansion(data, definitions)
        if !data.respond_to?(:to_str)
            return data
        end
        definitions = { 'HOME' => ENV['HOME'] }.merge(definitions)

        data = data.gsub /(.|^)\$(\w+)/ do |constant_name|
            prefix = constant_name[0, 1]
            if prefix == "\\"
                next(constant_name[1..-1])
            end
            if prefix == "$"
                prefix, constant_name = "", constant_name[1..-1]
            else
                constant_name = constant_name[2..-1]
            end

            if !(value = definitions[constant_name])
                if !(value = Autoproj.user_config(constant_name))
                    if !block_given? || !(value = yield(constant_name))
                        raise ArgumentError, "cannot find a definition for $#{constant_name}"
                    end
                end
            end
            "#{prefix}#{value}"
        end
        data
    end

    # Expand constants within +value+
    #
    # The list of constants is given in +definitions+. It raises ConfigError if
    # some values are not found
    def self.expand(value, definitions = Hash.new)
        if value.respond_to?(:to_hash)
            value.dup.each do |name, definition|
                value[name] = expand(definition, definitions)
            end
            value
        elsif value.respond_to?(:to_ary)
            value.map { |val| expand(val, definitions) }
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

    # Resolves all possible variable references from +constants+
    #
    # I.e. replaces variables by their values, so that no value in +constants+
    # refers to variables defined in +constants+
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
                    if name_match =~ /[^\w\/_-]/
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

    # Class used to store information about a package definition
    class PackageDefinition
        attr_reader :autobuild
        attr_reader :user_blocks
        attr_reader :package_set
        attr_reader :file
        def setup?; !!@setup end
        attr_writer :setup
        attr_accessor :vcs

        def initialize(autobuild, package_set, file)
            @autobuild, @package_set, @file =
                autobuild, package_set, file
            @user_blocks = []
        end

        def name
            autobuild.name
        end

        def add_setup_block(block)
            user_blocks << block
            if setup?
                block.call(autobuild)
            end
        end
    end

    # A set of packages that can be referred to by name
    class Metapackage
        # The metapackage name
        attr_reader :name
        # The packages listed in this metapackage
        attr_reader :packages

        def initialize(name)
            @name = name
            @packages = []
        end
        # Adds a package to this metapackage
        def add(pkg)
            @packages << pkg
        end
        def each_package(&block)
            @packages.each(&block)
        end
        def include?(pkg)
            if !pkg.respond_to?(:to_str)
                pkg = pkg.name
            end
            @packages.any? { |p| p.name == pkg }
        end
    end

    # The Manifest class represents the information included in the main
    # manifest file, and allows to manipulate it
    class Manifest

        # Data structure used to use autobuild importers without a package, to
        # import configuration data.
        #
        # It has to match the interface of Autobuild::Package that is relevant
        # for importers
        class FakePackage < Autobuild::Package
            attr_reader :srcdir
            attr_reader :importer

            # Used by the autobuild importers
            attr_accessor :updated

            def initialize(text_name, srcdir, importer = nil)
                super(text_name)
                @srcdir = srcdir
                @importer = importer
                @@packages.delete(text_name)
            end

            def import
                importer.import(self)
            end

            def add_stat(*args)
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
                raise ConfigError.new(File.dirname(file)), "expected an autoproj configuration in #{File.dirname(file)}, but #{file} does not exist"
            end

            data = Autoproj.in_file(file, Autoproj::YAML_LOAD_ERROR) do
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

        attr_reader :metapackages

	def initialize
            @file = nil
	    @data = nil
            @packages = Hash.new
            @package_manifests = Hash.new
            @automatic_exclusions = Hash.new
            @constants_definitions = Hash.new
            @disabled_imports = Set.new
            @moved_packages = Hash.new
            @osdeps_overrides = Hash.new
            @metapackages = Hash.new
            @ignored_os_dependencies = Set.new

            @constant_definitions = Hash.new
            if Autoproj.has_config_key?('manifest_source')
                @vcs = VCSDefinition.from_raw(Autoproj.user_config('manifest_source'))
            end
	end


        # Call this method to ignore a specific package. It must not be used in
        # init.rb, as the manifest is not yet loaded then
        def ignore_package(package_name)
            list = (data['ignore_packages'] ||= Array.new)
            list << package_name
        end

        # True if the given package should not be built, with the packages that
        # depend on him have this dependency met.
        #
        # This is useful if the packages are already installed on this system.
        def ignored?(package_name)
            if data['ignore_packages']
                data['ignore_packages'].any? do |l|
                    if package_name == l
                        true
                    elsif (pkg_set = metapackages[l]) && pkg_set.include?(package_name)
                        true
                    else
                        false
                    end
                end
            else
                false
            end
        end

        # Removes all registered exclusions
        def clear_exclusions
            automatic_exclusions.clear
            if excl = data['exclude_packages']
                excl.clear
            end
        end

        # Removes all registered ignored packages
        def clear_ignored
            if ignored = data['ignore_packages']
                ignored.clear
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
                return enum_for(:each_source_file, source_name)
            end

            # This looks very inefficient, but it is because source names are
            # contained in source.yml and we must therefore load that file to
            # check the package set name ...
            #
            # And honestly I don't think someone will have 20 000 package sets
            done_something = false
            each_package_set(false) do |source| 
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
                return enum_for(:each_source_file)
            end

            each_package_set(false) do |source|
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

        # Like #each_package_set, but filters out local package sets
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
            @package_sets.each do |pkg_set|
                @metapackages[pkg_set.name] ||= Metapackage.new(pkg_set.name)
                @metapackages["#{pkg_set.name}.all"] ||= Metapackage.new("#{pkg_set.name}.all")
            end
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

        def definition_source(package_name)
            if pkg_def = @packages[package_name]
                pkg_def.package_set
            end
        end
        def definition_file(package_name)
            if pkg_def = @packages[package_name]
                pkg_def.file
            end
        end

        def package(name)
            packages[name]
        end

        # Lists all defined packages as PackageDefinition objects
        def each_package_definition(&block)
            if !block_given?
                return enum_for(:each_package_definition)
            end
            packages.each_value(&block)
        end

        # Lists all defined autobuild packages as instances of
        # Autobuild::Package and its subclasses
        def each_autobuild_package
            if !block_given?
                return enum_for(:each_package)
            end
            packages.each_value { |pkg| yield(pkg.autobuild) }
        end

        # DEPRECATED: use either #each_autobuild_package and
        # #each_package_definition
        def each_package(&block)
            each_autobuild_package(&block)
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
                        Autoproj.message "  #{pkg_set.imported_from.name}: auto-importing #{pkg_set.name}"
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

            sources = each_package_set.to_a.dup

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
            vcs_spec, raw = Autoproj.in_file package_source.source_file do
                package_source.version_control_field(package_name, 'version_control')
            end
            return if !vcs_spec

            sources.each do |src|
                overrides_spec, raw_additional = src.version_control_field(package_name, 'overrides', false)
                raw = raw.concat(raw_additional)
                if overrides_spec
                    vcs_spec = Autoproj.in_file src.source_file do
                        begin
                            VCSDefinition.update_raw_vcs_spec(vcs_spec, overrides_spec)
                        rescue ConfigError => e
                            raise ConfigError.new, "invalid resulting VCS specification in the overrides section for package #{package_name}: #{e.message}"
                        end
                    end
                end
            end
            VCSDefinition.from_raw(vcs_spec, raw)
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

        # Returns true if +name+ is the name of a package set known to this
        # autoproj installation
        def has_package_set?(name)
            each_package_set(false).find { |set| set.name == name }
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
        def resolve_package_name(name)
            if pkg_set = find_metapackage(name)
                if !pkg_set
                    raise ConfigError.new, "#{name} is neither a package nor a package set name. Packages in autoproj must be declared in an autobuild file."
                end
                pkg_names = pkg_set.each_package.map(&:name)
            else
                pkg_names = [name]
            end

            result = []
            pkg_names.each do |pkg|
                result.concat(resolve_single_package_name(pkg))
            end
            result
        end

        # Resolves all the source-based dependencies of this package (excluding
        # the OS dependencies). The result is returned as a set of package
        # names.
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
        def resolve_single_package_name(name) # :nodoc:
            if ignored?(name)
                return []
            end

            explicit_selection  = explicitly_selected_package?(name)
	    osdeps_availability = Autoproj.osdeps.availability_of(name)
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

                # No source, no osdeps. Call osdeps again, but this time to get
                # a proper error message.
                if !available_as_source
                    begin
                        Autoproj.osdeps.resolve_os_dependencies([name].to_set)
                    rescue Autoproj::ConfigError => e
                        if osdeps_availability != Autoproj::OSDependencies::NO_PACKAGE && !Autoproj.osdeps.installs_os_packages?
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
                    raise ConfigError.new, "#{name} is neither a package nor a package set name. Packages in autoproj must be declared in an autobuild file."
                end
                pkg_set.each_package.
                    map(&:name).
                    find_all { |pkg_name| !Autoproj.osdeps || !Autoproj.osdeps.has?(pkg_name) }
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

        # Returns the packages contained in the provided layout definition
        #
        # If recursive is false, yields only the packages at this level.
        # Otherwise, return all packages.
        def layout_packages(validate)
            result = PackageSelection.new
            Autoproj.in_file(self.file) do
                normalized_layout.each_key do |pkg_or_set|
                    result.select(pkg_or_set, resolve_package_set(pkg_or_set))
                end
            end
            
            begin
                result.filter_excluded_and_ignored_packages(self)
            rescue ConfigError
                raise if validate
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
            if !Autobuild::Package[name] && !Autoproj.osdeps.has?(name)
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
            result = Set.new
            root = default_packages.packages.to_set
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
                set_name = definition_source(package_name).name
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
                    Autoproj.warn "#{package.name} from #{package_set.name} does not have a manifest"
                    PackageManifest.new(package)
                else
                    PackageManifest.load(package, manifest_path)
                end

            pkg.autobuild.description = manifest
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

        # Installs the OS dependencies that are required by the given packages
        def install_os_dependencies(packages)
            required_os_packages, package_os_deps = list_os_dependencies(packages)
            required_os_packages.delete_if do |pkg|
                if excluded?(pkg)
                    raise ConfigError.new, "the osdeps package #{pkg} is excluded from the build in #{file}. It is required by #{package_os_deps[pkg].join(", ")}"
                end
                if ignored?(pkg)
                    if Autoproj.verbose
                        Autoproj.message "ignoring osdeps package #{pkg}"
                    end
                    true
                end
            end
            Autoproj.osdeps.install(required_os_packages, package_os_deps)
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

        # Class holding information about which packages have been selected, and
        # why. It is used to decide whether some non-availability of packages
        # are errors or simply warnings (i.e. if the user really wants a given
        # package, or merely might be adding it by accident)
        class PackageSelection
            # The set of matches, i.e. a mapping from a user-provided string to
            # the set of packages it selected
            attr_reader :matches
            # The set of selected packages, as a hash of the package name to the
            # set of user-provided strings that caused that package to be
            # selected
            attr_reader :selection

            # The set of packages that have been selected
            def packages
                selection.keys
            end

            def include?(pkg_name)
                selection.has_key?(pkg_name)
            end

            def empty?
                selection.empty?
            end

            def initialize
                @selection = Hash.new { |h, k| h[k] = Set.new }
                @matches = Hash.new { |h, k| h[k] = Set.new }
            end

            def select(sel, packages)
                if !packages.respond_to?(:each)
                    matches[sel] << packages
                    selection[packages] << sel
                else
                    matches[sel] |= packages.to_set
                    packages.each do |pkg_name|
                        selection[pkg_name] << sel
                    end
                end
            end

            def initialize_copy(old)
                old.selection.each do |pkg_name, set|
                    @selection[pkg_name] = set.dup
                end
                old.matches.each do |sel, set|
                    @matches[sel] = set.dup
                end
            end

            # Remove packages that are explicitely excluded and/or ignored
            #
            # Raise an error if an explicit selection expands only to an
            # excluded package, and display a warning for ignored packages
            def filter_excluded_and_ignored_packages(manifest)
                matches.each do |sel, expansion|
                    excluded, other = expansion.partition { |pkg_name| manifest.excluded?(pkg_name) }
                    ignored,  ok    = other.partition { |pkg_name| manifest.ignored?(pkg_name) }

                    if ok.empty? && ignored.empty?
                        exclusions = excluded.map do |pkg_name|
                            [pkg_name, manifest.exclusion_reason(pkg_name)]
                        end
                        if exclusions.size == 1
                            reason = exclusions[0][1]
                            if sel == exclusions[0][0]
                                raise ConfigError.new, "#{sel} is excluded from the build: #{reason}"
                            else
                                raise ConfigError.new, "#{sel} expands to #{exclusions.map(&:first).join(", ")}, which is excluded from the build: #{reason}"
                            end
                        else
                            raise ConfigError.new, "#{sel} expands to #{exclusions.map(&:first).join(", ")}, and all these packages are excluded from the build:\n  #{exclusions.map { |name, reason| "#{name}: #{reason}" }.join("\n  ")}"
                        end
                    elsif !ignored.empty?
                        ignored.each do |pkg_name|
                            Autoproj.warn "#{pkg_name} was selected for #{sel}, but is explicitely ignored in the manifest"
                        end
                    end

                    excluded = excluded.to_set
                    expansion.delete_if do |pkg_name|
                        excluded.include?(pkg_name)
                    end
                end

                selection.keys.sort.each do |pkg_name|
                    if manifest.excluded?(pkg_name)
                        Autoproj.warn "#{pkg_name} was selected for #{selection[pkg_name].to_a.sort.join(", ")}, but it is excluded from the build: #{Autoproj.manifest.exclusion_reason(pkg_name)}"
                        selection.delete(pkg_name)
                    elsif manifest.ignored?(pkg_name)
                        Autoproj.warn "#{pkg_name} was selected for #{selection[pkg_name].to_a.sort.join(", ")}, but it is ignored in this build"
                        selection.delete(pkg_name)
                    end
                end
            end
        end

        # Package selection can be done in three ways:
        #  * as a subdirectory in the layout
        #  * as a on-disk directory
        #  * as a package name
        #
        # This method converts the first two directories into the third one
        def expand_package_selection(selection)
            base_dir = Autoproj.root_dir

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
                        result.select(sel, packages)
                    end
                end
            end

            # Finally, check for package source directories
            all_packages = self.all_package_names
            selection.each do |sel|
                match_pkg_name = Regexp.new(Regexp.quote(sel))
                all_packages.each do |pkg_name|
                    pkg = Autobuild::Package[pkg_name]
                    if pkg_name =~ match_pkg_name || "#{sel}/" =~ Regexp.new("^#{Regexp.quote(pkg.srcdir)}/") || pkg.srcdir =~ Regexp.new("^#{Regexp.quote(sel)}")
                        # Check-out packages that are not in the manifest only
                        # if they are explicitely selected
                        if !all_layout_packages.include?(pkg.name)
                            if pkg_name != sel && pkg.srcdir != sel
                                next
                            end
                        end

                        result.select(sel, pkg_name)
                    end
                end
            end

            result.filter_excluded_and_ignored_packages(self)
            return result, (selection - result.matches.keys)
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

    # Access to the information contained in a package's manifest.xml file
    #
    # Use PackageManifest.load to create
    class PackageManifest
        # Load a manifest.xml file and returns the corresponding
        # PackageManifest object
        def self.load(package, file)
            doc =
                begin REXML::Document.new(File.read(file))
                rescue REXML::ParseException => e
                    raise Autobuild::PackageException.new(package.name, 'prepare'), "invalid #{file}: #{e.message}"
                end

            PackageManifest.new(package, doc)
        end

        # The Autobuild::Package instance this manifest applies on
        attr_reader :package
        # The raw XML data as a Nokogiri document
        attr_reader :xml

        # The list of tags defined for this package
        #
        # Tags are defined as multiple <tags></tags> blocks, each of which can
        # contain multiple comma-separated tags 
        def tags
            result = []
            xml.elements.each('package/tags') do |node|
                result.concat((node.text || "").strip.split(','))
            end
            result
        end

        def documentation
            xml.elements.each('package/description') do |node|
                doc = (node.text || "").strip
                if !doc.empty?
                    return doc
                end
            end
            return short_documentation
        end

        def short_documentation
            xml.elements.each('package/description') do |node|
                doc = node.attributes['brief']
                if doc
                    doc = doc.to_s.strip
                end
                if doc && !doc.empty?
                    return doc.to_s
                end
            end
            "no documentation available for #{package.name} in its manifest.xml file"
        end

        def initialize(package, doc = REXML::Document.new)
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
                xml.elements.each('package/rosdep') do |node|
                    yield(node.attributes['name'], false)
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
                depend_nodes = xml.elements.to_a('package/depend') +
                    xml.elements.to_a('package/depend_optional')

                depend_nodes.each do |node|
                    dependency = node.attributes['package']
                    optional = (node.attributes['optional'].to_s == '1' || node.name == "depend_optional")

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

        # Enumerates the name and email of each author. If no email is present,
        # yields (name, nil)
        def each_author
            if !block_given?
                return enum_for(:each_author)
            end

            xml.elements.each('package/author') do |author|
                (author.text || "").strip.split(',').each do |str|
                    name, email = str.split('/').map(&:strip)
                    email = nil if email && email.empty?
                    yield(name, email)
                end
            end
        end

        # If +name+ points to a text element in the XML document, returns the
        # content of that element. If no element matches +name+, or if the
        # content is empty, returns nil
        def text_node(name)
            xml.elements.each(name) do |str|
                str = (str.text || "").strip
                if !str.empty?
                    return str
                end
            end
            nil
        end

        # The package associated URL, usually meant to direct to a website
        #
        # Returns nil if there is none
        def url
            return text_node('package/url')
        end

        # The package license name
        #
        # Returns nil if there is none
        def license
            return text_node('package/license')
        end

        # The package version number
        #
        # Returns 0 if none is declared
        def version
            return text_node("version")
        end
    end
    def self.add_osdeps_overrides(*args, &block)
        manifest.add_osdeps_overrides(*args, &block)
    end
end

