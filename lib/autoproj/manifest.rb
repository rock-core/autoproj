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
                raise ConfigError, "version control #{type} is unknown to autoproj"
            end
        end

        def local?
            @type == 'local'
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
                    desc = "#{desc} #{options.map { |key, value| "#{key}=#{value}" }.join(" ")}"
                end
                desc
            end
        end
    end

    def self.vcs_definition_to_hash(spec)
        if spec.respond_to?(:to_str)
            vcs, *url = spec.to_str.split ':'
            spec = if url.empty?
                       source_dir = File.expand_path(File.join(Autoproj.config_dir, spec))
                       if !File.directory?(source_dir)
                           raise ConfigError, "'#{spec.inspect}' is neither a remote source specification, nor a local source definition"
                       end

                       Hash[:type => 'local', :url => source_dir]
                   else
                       Hash[:type => vcs.to_str, :url => url.join(":").to_str]
                   end
        end

        spec, vcs_options = Kernel.filter_options spec, :type => nil, :url => nil

        return spec.merge(vcs_options)
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
            raise ConfigError, "the source specification #{spec.inspect} misses either the VCS type or an URL"
        end

        spec, vcs_options = Kernel.filter_options spec, :type => nil, :url => nil
        return VCSDefinition.new(spec[:type], spec[:url], vcs_options)
    end

    def self.single_expansion(data, definitions)
        if !data.respond_to?(:to_str)
            return data
        end

        definitions.each do |name, expanded|
            data = data.gsub /\$#{Regexp.quote(name)}\b/, expanded
        end
        data
    end

    # A source is a version control repository which contains general source
    # information with package version control information (source.yml file),
    # package definitions (.autobuild files), and finally definition of
    # dependencies that are provided by the operating system (.osdeps file).
    class Source
        # The VCSDefinition object that defines the version control holding
        # information for this source. Local package sets (i.e. the ones that are not
        # under version control) use the 'local' version control name. For them,
        # local? returns true.
        attr_accessor :vcs
        attr_reader :source_definition
        attr_reader :constants_definitions

        # Create this source from a VCSDefinition object
        def initialize(vcs)
            @vcs = vcs
        end

        # True if this source has already been checked out on the local autoproj
        # installation
        def present?; File.directory?(raw_local_dir) end
        # True if this source is local, i.e. is not under a version control
        def local?; vcs.local? end
        # True if this source defines nothing
        def empty?
            !source_definition['version_control'] &&
                !each_package.find { true } &&
                !File.exists?(File.join(raw_local_dir, "overrides.rb")) &&
                !File.exists?(File.join(raw_local_dir, "init.rb"))
        end

        def raw_local_dir
            if local?
                return vcs.url 
            else
                File.join(Autoproj.remotes_dir, automatic_name)
            end
        end

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

        # A name generated from the VCS url
        def automatic_name
            vcs.to_s.gsub(/[^\w]/, '_')
        end

        # Returns the source name
        def name
            if @source_definition then
                @source_definition['name'] || automatic_name
            elsif @name
                @name
            else
                automatic_name
            end
        end

        def raw_description_file
            if !present?
                raise InternalError, "source #{vcs} has not been fetched yet, cannot load description for it"
            end

            source_file = File.join(raw_local_dir, "source.yml")
            if !File.exists?(source_file)
                raise ConfigError, "source #{vcs.type}:#{vcs.url} should have a source.yml file, but does not"
            end

            begin
                source_definition = YAML.load(File.read(source_file))
            rescue ArgumentError => e
                raise ConfigError, "error in #{source_file}: #{e.message}"
            end

            if !source_definition || !source_definition['name']
                raise ConfigError, "#{source_file} does not have a 'name' field"
            end

            source_definition
        end

        # Load and validate the name from the YAML hash
        def load_name
            definition = @source_definition || raw_description_file
            @name = definition['name']

            if @name !~ /^[\w_\.-]+$/
                raise ConfigError, "invalid source name '#{@name}': source names can only contain alphanumeric characters, and .-_"
            elsif @name == "local"
                raise ConfigError, "source #{self} is named 'local', but this is a reserved name"
            end

        rescue InternalError
        end

        def source_file
            File.join(local_dir, 'source.yml')
        end

        # Load the source.yml file that describes this source, and resolve the
        # $BLABLA values that are in there. Use #raw_description_file to avoid
        # resolving those values
        def load_description_file
            @source_definition = raw_description_file
            load_name

            # Compute the definition of constants
            begin
                constants = source_definition['constants'] || Hash.new
                constants['HOME'] = ENV['HOME']

                redo_expansion = true
                @constants_definitions = constants 
                while redo_expansion
                    redo_expansion = false
                    constants.dup.each do |name, url|
                        # Extract all expansions in the url
                        if url =~ /\$(\w+)/
                            expansion_name = $1

                            if constants[expansion_name]
                                constants[name] = single_expansion(url)
                            else
                                begin constants[name] = single_expansion(url,
                                                 expansion_name => Autoproj.user_config(expansion_name))
                                rescue ConfigError => e
                                    raise ConfigError, "constant '#{expansion_name}', used in the definition of '#{name}' is defined nowhere"
                                end
                            end
                            redo_expansion = true
                        end
                    end
                end

            rescue ConfigError => e
                raise ConfigError, "#{File.join(local_dir, "source.yml")}: #{e.message}", e.backtrace
            end
        end

        # True if the given string contains expansions
        def contains_expansion?(string); string =~ /\$/ end

        def single_expansion(data, additional_expansions = Hash.new)
            Autoproj.single_expansion(data, additional_expansions.merge(constants_definitions))
        end

        # Expands the given string as much as possible using the expansions
        # listed in the source.yml file, and returns it. Raises if not all
        # variables can be expanded.
        def expand(data, additional_expansions = Hash.new)
            if !source_definition
                load_description_file
            end

            if data.respond_to?(:to_hash)
                data.dup.each do |name, value|
                    data[name] = expand(value, additional_expansions)
                end
            else
                data = single_expansion(data, additional_expansions)
                if contains_expansion?(data)
                    raise ConfigError, "some expansions are not defined in #{data.inspect}"
                end
            end

            data
        end

        # Returns an importer definition for the given package, if one is
        # available. Otherwise returns nil.
        #
        # The returned value is a VCSDefinition object.
        def importer_definition_for(package_name)
            urls = source_definition['urls'] || Hash.new
            urls['HOME'] = ENV['HOME']

            all_vcs     = source_definition['version_control']
            if all_vcs
                if all_vcs.kind_of?(Hash)
                    raise ConfigError, "wrong format for the version_control field, you forgot the '-' in front of the package names"
                elsif !all_vcs.kind_of?(Array)
                    raise ConfigError, "wrong format for the version_control field"
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
                                raise ConfigError, "invalid VCS specification '#{name}: #{spec}'"
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
                vcs_spec

                Autoproj.normalize_vcs_definition(vcs_spec)
            end
        rescue ConfigError => e
            raise ConfigError, "#{e.message} in #{source_file}", e.backtrace
        end

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
    end

    class LocalSource < Source
        def initialize
            super(Autoproj.normalize_vcs_definition(:type => 'local', :url => Autoproj.config_dir))
        end

        def name
            'local'
        end
        def load_name
        end

        def source_file
            File.join(Autoproj.config_dir, "overrides.yml")
        end

        def raw_description_file
            path = source_file
            if File.file?(path)
                begin
                    data = YAML.load(File.read(path)) || Hash.new
                rescue ArgumentError => e
                    raise ConfigError, "error in #{source_file}: #{e.message}"
                end
                data['name'] = 'local'
                data
            else
                { 'name' => 'local' }
            end
        end
    end

    PackageDefinition = Struct.new :autobuild, :user_block, :package_set, :file

    class Manifest
        FakePackage = Struct.new :text_name, :name, :srcdir, :importer, :updated
        class FakePackage
            def autoproj_name; name end
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

	def self.load(file)
            begin
                data = YAML.load(File.read(file))
            rescue Errno::ENOENT
                raise ConfigError, "expected an autoproj configuration in #{File.expand_path(File.dirname(file))}, but #{file} does not exist"
            rescue ArgumentError => e
                raise ConfigError, "error in #{file}: #{e.message}"
            end
	    Manifest.new(file, data)
	end

        # The manifest data as a Hash
        attr_reader :data

        # The set of packages defined so far as a mapping from package name to 
        # [Autobuild::Package, source, file] tuple
        attr_reader :packages

        # A mapping from package names into PackageManifest objects
        attr_reader :package_manifests

        attr_reader :file

        def auto_update?
            !!data['auto_update']
        end

	def initialize(file, data)
            @file = file
	    @data = data
            @packages = Hash.new
            @package_manifests = Hash.new

            if Autoproj.has_config_key?('manifest_source')
                @vcs = Autoproj.normalize_vcs_definition(Autoproj.user_config('manifest_source'))
            end
	end

        # True if the given package should not be built, with the packages that
        # depend on him have this dependency met.
        #
        # This is useful if the packages are already installed on this system.
        def ignored?(package_name)
            if data['ignored_packages']
                data['ignored_packages'].any? { |l| Regexp.new(l) =~ package_name }
            else
                false
            end
        end
        # True if the given package should not be built and its dependencies
        # should be considered as met.
        #
        # This is useful to avoid building packages that are of no use for the
        # user.
        def excluded?(package_name)
            if data['excluded_packages']
                data['excluded_packages'].any? { |l| Regexp.new(l) =~ package_name }
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
                raise ConfigError, "source '#{source_name}' does not exist"
            end
	end

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

        def has_remote_sources?
            each_remote_source(false).any? { true }
        end

        # Like #each_source, but filters out local package sets
        def each_remote_source(load_description = true)
            if !block_given?
                enum_for(:each_remote_source, load_description)
            else
                each_source(load_description) do |source|
                    if !source.local?
                        yield(source)
                    end
                end
            end
        end

        def source_from_spec(spec, load_description) # :nodoc:
            # Look up for short notation (i.e. not an explicit hash). It is
            # either vcs_type:url or just url. In the latter case, we expect
            # 'url' to be a path to a local directory
            vcs_def = begin
                          Autoproj.normalize_vcs_definition(spec)
                      rescue ConfigError => e
                          raise ConfigError, "in #{file}: #{e.message}"
                      end

            source = Source.new(vcs_def)
            if load_description
                if source.present?
                    source.load_description_file
                else
                    raise InternalError, "cannot load description file as it has not been checked out yet"
                end
            else
                # Try to load just the name from the source.yml file
                source.load_name
            end

            source
        end


        # call-seq:
        #   each_source { |source_description| ... }
        #
        # Lists all package sets defined in this manifest, by yielding a Source
        # object that describes it.
        def each_source(load_description = true, &block)
            if !block_given?
                return enum_for(:each_source, load_description)
            end

            if @sources
                return @sources.each(&block)
            end

            all_sources = []

	    (data['package_sets'] || []).each do |spec|
                all_sources << source_from_spec(spec, load_description)
            end

            # Now load the local source 
            local = LocalSource.new
            if load_description
                local.load_description_file
            else
                local.load_name
            end
            if !load_description || !local.empty?
                all_sources << local
            end

            all_sources.each(&block)
            if load_description
                @sources = all_sources
            end
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
                yield(vcs, "autoproj main configuration", "autoproj_config", Autoproj.config_dir)
            end

            each_remote_source(false) do |source|
                yield(source.vcs, source.name || source.vcs.url, source.automatic_name, source.local_dir)
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
        def self.create_autobuild_package(vcs, text_name, pkg_name, into)
            importer     = vcs.create_autobuild_importer
            return if !importer # updates have been disabled by using the 'none' type

            fake_package = FakePackage.new(text_name, pkg_name, into)
            fake_package.importer = importer
            fake_package

        rescue Autobuild::ConfigException => e
            raise ConfigError, "cannot import #{name}: #{e.message}", e.backtrace
        end

        # Imports or updates a source (remote or otherwise).
        #
        # See create_autobuild_package for informations about the arguments.
        def self.update_source(vcs, text_name, pkg_name, into)
            fake_package = create_autobuild_package(vcs, text_name, pkg_name, into)
            fake_package.import

        rescue Autobuild::ConfigException => e
            raise ConfigError, "cannot import #{name}: #{e.message}", e.backtrace
        end

        # Updates the main autoproj configuration
        def update_yourself
            Manifest.update_source(vcs, "autoproj main configuration", "autoproj_conf", Autoproj.config_dir)
        end

        # Updates all the remote sources in ROOT_DIR/.remotes, as well as the
        # symbolic links in ROOT_DIR/autoproj/remotes
        def update_remote_sources
            # Iterate on the remote sources, without loading the source.yml
            # file (we're not ready for that yet)
            sources = []
            each_remote_source(false) do |source|
                Manifest.update_source(source.vcs, source.name || source.vcs.url, source.automatic_name, source.raw_local_dir)
                sources << source
            end

            # Check for directories in ROOT_DIR/.remotes that do not map to a
            # source repository, and remove them
            Dir.glob(File.join(Autoproj.remotes_dir, '*')).each do |dir|
                dir = File.expand_path(dir)
                if File.directory?(dir) && !sources.any? { |s| s.raw_local_dir == dir }
                    FileUtils.rm_rf dir
                end
            end

            remotes_symlinks_dir = File.join(Autoproj.config_dir, 'remotes')
            FileUtils.rm_rf remotes_symlinks_dir
            FileUtils.mkdir remotes_symlinks_dir
            # Create symbolic links from .remotes/weird_url to
            # autoproj/remotes/name
            each_remote_source(false) do |source|
                FileUtils.ln_sf source.raw_local_dir, File.join(remotes_symlinks_dir, source.name)
            end
        end

        def importer_definition_for(package_name, package_source = nil)
            if !package_source
                package_source = packages.values.
                    find { |pkg| pkg.autobuild.name == package_name }.
                    package_set
            end

            each_source.to_a.reverse.each do |source|
                vcs = source.importer_definition_for(package_name)
                if vcs
                    return vcs
                elsif package_source.name == source.name
                    return
                end
            end
            nil
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
                vcs = importer_definition_for(pkg.autobuild.name, pkg.package_set)

                if vcs
                    Autoproj.add_build_system_dependency vcs.type
                    pkg.autobuild.importer = vcs.create_autobuild_importer
                else
                    raise ConfigError, "source #{pkg.package_set.name} defines #{pkg.autobuild.name}, but does not provide a version control definition for it"
                end
            end
        end

        # +name+ can either be the name of a source or the name of a package. In
        # the first case, we return all packages defined by that source. In the
        # latter case, we return the singleton array [name]
        def resolve_package_set(name)
            if Autobuild::Package[name]
                [name]
            else
                source = each_source.find { |source| source.name == name }
                if !source
                    raise ConfigError, "#{name} is neither a package nor a source"
                end
                packages.values.
                    map { |pkg| pkg.autobuild.name if pkg.package_set.name == source.name }.
                    compact
            end
        end

        # Returns the packages contained in the provided layout definition
        #
        # If recursive is false, yields only the packages at this level.
        # Otherwise, return all packages.
        def layout_packages(layout_def, recursive)
            result = []
            layout_def.each do |value|
                if !value.kind_of?(Hash) # sublayout
                    result.concat(resolve_package_set(value))
                end
            end

            if recursive
                each_sublayout(layout_def) do |sublayout_name, sublayout_def|
                    result.concat(layout_packages(sublayout_def, true))
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

        # Looks into the layout setup in the manifest, and yields each layout
        # and sublayout in order
        def each_package_set(selection = nil, layout_name = '/', layout_def = data['layout'], &block)
            if !layout_def
                yield(layout_name, default_packages, default_packages)
                return nil
            end

            selection = selection.to_set if selection

            # First of all, do the packages at this level
            packages = layout_packages(layout_def, false)
            # Remove excluded packages
            packages.delete_if { |pkg_name| excluded?(pkg_name) }

            if selection
                selected_packages = packages.find_all { |pkg_name| selection.include?(pkg_name) }
            else
                selected_packages = packages.dup
            end
            if !packages.empty?
                yield(layout_name, packages.to_set, selected_packages.to_set)
            end

            # Now, enumerate the sublayouts
            each_sublayout(layout_def) do |subname, sublayout|
                each_package_set(selection, "#{layout_name}#{subname}/", sublayout, &block)
            end
        end

        def in_sublayout(name, packages)
            srcdir  = File.join(Autoproj.root_dir, name)
            prefix  = File.join(Autoproj.build_dir, name)
            logdir  = File.join(prefix, "log")
            Autobuild.logdir = logdir
            packages.each do |pkg_name|
                pkg = Autobuild::Package[pkg_name]
                pkg.srcdir = File.join(srcdir, pkg_name)
                pkg.prefix = prefix
                pkg.logdir = logdir
            end

            yield
        end

        def default_packages
            names = if layout = data['layout']
                        layout_packages(layout, true)
                    else
                        # No layout, all packages are selected
                        packages.values.
                            map { |pkg| pkg.autobuild.name }
                    end
            names = names.delete_if { |pkg_name| excluded?(pkg_name) }
            names.to_set
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

            manifest.each_dependency do |name|
                begin
                    package.depends_on name
                rescue Autobuild::ConfigException => e
                    raise ConfigError, "manifest of #{package.name} from #{source.name} lists '#{name}' as dependency, but this package does not exist (manifest file: #{manifest_path})"
                end
            end
        end

        # Loads the manifests for all packages known to this project.
        #
        # See #load_package_manifest
        def load_package_manifests(selected_packages)
            selected_packages.each(&:load_package_manifest)
        end

        # Returns an OSDependencies instance that defined the known OS packages,
        # as well as how to install them
        def known_os_packages
            osdeps = OSDependencies.load_default

            each_osdeps_file do |source, file|
                osdeps.merge(OSDependencies.load(file))
            end
            osdeps
        end

        def install_os_dependencies(packages)
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

            known_os_packages.install(required_os_packages, package_os_deps)
        end

        # Package selection can be done in three ways:
        #  * as a subdirectory in the layout
        #  * as a on-disk directory
        #  * as a package name
        #
        # This method converts the first two directories into the third one
        def expand_package_selection(selected_packages)
            base_dir = Autoproj.root_dir

            expanded_packages = []

            # Get all the package names
            package_names = Autobuild::Package.each(true).
                map do |name, pkg|
                    pkg.name
                end

            # First, remove packages that are directly referenced by name or by
            # package set names
            selected_packages.delete_if do |sel|
                sel = Regexp.new(Regexp.quote(sel))

                packages = package_names.find_all { |pkg_name| pkg_name =~ sel }
                expanded_packages.concat(packages)

                sources = each_source.find_all { |source| source.name =~ sel }
                sources.each do |source|
                    expanded_packages.concat(resolve_package_set(source.name))
                end

                !packages.empty? && !sources.empty?
            end

            if selected_packages.empty?
                return expanded_packages
            end

            # Now, expand sublayout and directory names 
            each_package_set(nil) do |layout_name, packages, _|
                selected_packages.delete_if do |sel|
                    if layout_name[0..-1] =~ Regexp.new("#{sel}\/?$")
                        expanded_packages.concat(packages.to_a)
                    else
                        match = Regexp.new("^#{Regexp.quote(sel)}")
                        Autobuild::Package.each(true) do |name, pkg|
                            if pkg.srcdir =~ match
                                expanded_packages << name
                            end
                        end
                    end
                end
            end
            expanded_packages.to_set
        end
    end

    class << self
        # The singleton manifest object on which the current run works
        attr_accessor :manifest

        # The operating system package definitions
        attr_accessor :osdeps
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
                    yield(node['name'])
                end
                package.os_packages.each do |name|
                    yield(name)
                end
            else
                enum_for :each_os_dependency
            end
        end

        def each_package_dependency
            if block_given?
                xml.xpath('//depend').each do |node|
                    dependency = node['package']
                    if dependency
                        yield(dependency)
                    else
                        raise ConfigError, "manifest of #{package.name} has a <depend> tag without a 'package' attribute"
                    end
                end
            else
                enum_for :each_package_dependency
            end
        end
    end
end

