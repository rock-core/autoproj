module Autoproj
    # Class that does the handling of configuration options as well as
    # loading/saving on disk
    class Configuration
        # Set of currently known options
        #
        # These are the values that are going to be saved on disk. Use
        # {override} to change a value without changing the saved configuration
        # file.
        attr_reader :config
        # Set of overriden option values that won't get written to file
        attr_reader :overrides
        # Set of options that have been declared with {declare}
        attr_reader :declared_options
        # The options that have already been shown to the user
        attr_reader :displayed_options
        # The path to the underlying configuration file
        attr_reader :path

        def initialize(path = nil)
            @config = Hash.new
            @overrides = Hash.new
            @declared_options = Hash.new
            @displayed_options = Hash.new
            @path = path
        end

        # Deletes the current value for an option
        #
        # The user will be asked for a new value next time the option is needed
        #
        # @param [String] the option name
        # @return the deleted value
        def reset(name)
            config.delete(name)
        end

        # Sets a configuration option
        #
        # @param [String] key the option name
        # @param [Object] value the option value
        # @param [Boolean] user_validated if true, autoproj will not ask the
        #   user about this value next time it is needed. Otherwise, it will be
        #   asked about it, the new value being used as default
        def set(key, value, user_validated = false)
            config[key] = [value, user_validated]
        end

        # Override a known option value
        #
        # The new value will not be saved to disk, unlike with {set}
        def override(option_name, value)
            overrides[option_name] = value
        end

        # Tests whether a value is set for the given option name
        #
        # @return [Boolean]
        def has_value_for?(name)
            config.has_key?(name) || overrides.has_key?(name)
        end

        # Get the value for a given option
        def get(key, *default_value)
            if overrides.has_key?(key)
                return overrides[key]
            end

            value, validated = config[key]
            if value.nil? && !declared?(key) && !default_value.empty?
                default_value.first
            elsif value.nil? || (declared?(key) && !validated)
                value = configure(key)
            else
                if declared?(key) && (displayed_options[key] != value)
                    doc = declared_options[key].short_doc
                    if doc[-1, 1] != "?"
                        doc = "#{doc}:"
                    end
                    Autoproj.message "  #{doc} #{value}"
                    displayed_options[key] = value
                end
                value
            end
        end

        # Returns the option's name-value pairs for the options that do not
        # require user input
        def validated_values
            config.inject(Hash.new) do |h, (k, v)|
                h[k] =
                    if overrides.has_key?(k) then overrides[k]
                    elsif v.last || !declared?(k) then v.first
                    end
                h
            end
        end

        # Declare an option
        #
        # This declares a given option, thus allowing to ask the user about it
        #
        # @param [String] name the option name
        # @param [String] type the option type (can be 'boolean' or 'string')
        # @option options [String] :short_doc the one-line documentation string
        #   that is displayed when the user does not have to be queried. It
        #   defaults to the first line of :doc if not given
        # @option options [String] :doc the full option documentation. It is
        #   displayed to the user when he is explicitly asked about the option's
        #   value
        # @option options [Object] :default the default value this option should
        #   take
        # @option options [Array] :possible_values list of possible values (only
        #   if the option type is 'string')
        # @option options [Boolean] :lowercase (false) whether the user's input
        #   should be converted to lowercase before it gets validated / saved.
        # @option options [Boolean] :uppercase (false) whether the user's input
        #   should be converted to uppercase before it gets validated / saved.
        def declare(name, type, options, &validator)
            declared_options[name] = BuildOption.new(name, type, options, validator)
        end

        # Checks if an option exists
        # @return [Boolean]
        def declared?(name)
            declared_options.has_key?(name)
        end

        # Configures a given option by asking the user about its desired value
        #
        # @return [Object] the new option value
        # @raise ConfigError if the option is not declared
        def configure(option_name)
            if opt = declared_options[option_name]
                if current_value = config[option_name]
                    current_value = current_value.first
                end
                value = opt.ask(current_value)
                config[option_name] = [value, true]
                displayed_options[option_name] = value
                value
            else
                raise ConfigError.new, "undeclared option '#{option_name}'"
            end
        end

        def load(options = Hash.new)
            options = validate_options options,
                path: self.path,
                reconfigure: false

            if h = YAML.load(File.read(options[:path]))
                h.each do |key, value|
                    set(key, value, !options[:reconfigure])
                end
            end
        end

        def reconfigure!
            new_config = Hash.new
            config.each do |key, (value, user_validated)|
                new_config[key] = [value, false]
            end
            @config = new_config
        end

        def save(path = self.path)
            File.open(path, "w") do |io|
                h = Hash.new
                config.each do |key, value|
                    h[key] = value.first
                end

                io.write YAML.dump(h)
            end
        end

        def each_reused_autoproj_installation
            if has_value_for?('reused_autoproj_installations')
                get('reused_autoproj_installations').each(&proc)
            else [].each(&proc)
            end
        end

        def import_log_enabled?
            get('import_log_enabled', true)
        end

        def import_log_enabled=(value)
            set('import_log_enabled', !!value)
        end

        def ruby_executable
            if path = get('ruby_executable', nil)
                path
            else
                path = OSDependencies.autodetect_ruby_program
                set('ruby_executable', path, true)
                path
            end
        end

        def validate_ruby_executable
            if has_value_for?('ruby_executable')
                expected = get('ruby_executable')
                if expected != ruby_executable
                    raise ConfigError.new, "this autoproj installation was bootstrapped using #{expected}, but you are currently running under #{ruby_executable}. This is usually caused by calling a wrong gem program (for instance, gem1.8 instead of gem1.9.1)"
                end
            end
            set('ruby_executable', ruby_executable, true)
        end

        def use_prerelease?
            use_prerelease =
                if env_flag = ENV['AUTOPROJ_USE_PRERELEASE']
                    env_flag == '1'
                elsif has_value_for?('autoproj_use_prerelease')
                    get('autoproj_use_prerelease')
                end
            set "autoproj_use_prerelease", (use_prerelease ? true : false), true
            use_prerelease
        end

        def shell_helpers?
            get 'shell_helpers', true
        end

        def shell_helpers=(flag)
            set 'shell_helpers', flag, true
        end

        def apply_autobuild_configuration
            if has_value_for?('autobuild')
                params = get('autobuild')
                if params.kind_of?(Hash)
                    params.each do |k, v|
                        Autobuild.send("#{k}=", v)
                    end
                end
            end
        end

        # The directory in which packages will be installed.
        #
        # If it is a relative path, it is relative to the root dir of the
        # installation.
        #
        # The default is "install"
        #
        # @return [String]
        def prefix_dir
            get('prefix', 'install')
        end

        # Defines the temporary area in which packages should put their build
        # files
        #
        # If absolute, it is handled as {#prefix_dir}: the package name will be
        # appended to it. If relative, it is relative to the package's source
        # directory
        #
        # The default is "build"
        #
        # @return [String]
        def build_dir
            get('build', 'build')
        end

        # Returns true if there should be one prefix per package
        #
        # The default is false (disabled)
        #
        # @return [Boolean]
        def separate_prefixes?
            get('separate_prefixes', false)
        end

        # Controls whether there should be one prefix per package
        #
        # @see separate_prefixes?
        def separate_prefixes=(flag)
            set('separate_prefixes', flag, true)
        end

        # Returns true if packages and prefixes should be auto-generated, based
        # on the SHA of the package names. This is meant to be used for build
        # services that want to check that dependencies are properly set
        #
        # The default is false (disabled)
        #
        # @return [Boolean]
        def randomize_layout?
            get('randomize_layout', false)
        end

        # Sets whether the layout should be randomized
        #
        # @return [Boolean]
        # @see randomize_layout?
        def randomize_layout=(value)
            set('randomize_layout', value, true)
        end

        DEFAULT_UTILITY_SETUP = Hash[
            'doc' => true,
            'test' => false]

        # The configuration key that should be used to store the utility
        # enable/disable information 
        #
        # @param [String] the utility name
        # @return [String] the config key
        def utility_key(utility)
            "autoproj_#{utility}_utility"
        end

        # Returns whether a given utility is enabled for the package
        #
        # If there is no specific configuration for the package, uses the global
        # default set with utility_enable_all or utility_disable_all. If none of
        # these methods has been called, uses the default in
        # {DEFAULT_UTILITY_SETUP}
        #
        # @param [String] utility the utility name (e.g. 'doc' or 'test')
        # @param [String] package the package name
        # @return [Boolean] true if the utility should be enabled for the
        #   requested package and false otherwise
        def utility_enabled_for?(utility, package)
            utility_config = get(utility_key(utility), Hash.new)
            if utility_config.has_key?(package)
                utility_config[package]
            else get("#{utility_key(utility)}_default", DEFAULT_UTILITY_SETUP[utility])
            end
        end

        # Enables a utility for all packages
        #
        # This both sets the default value for all packages and resets all
        # package-specific values set with {utility_enable_for} and
        # {utility_disable_for}
        #
        # @param [String] utility the utility name (e.g. 'doc' or 'test')
        # @return [void]
        def utility_enable_all(utility)
            reset(utility_key(utility))
            set("#{utility_key(utility)}_default", true)
        end

        # Enables a utility for a set of packages
        #
        # @param [String] utility the utility name (e.g. 'doc' or 'test')
        # @param [String] packages the package names
        # @return [void]
        def utility_enable(utility, *packages)
            utility_config = get(utility_key(utility), Hash.new)
            packages.each do |pkg_name|
                utility_config[pkg_name] = true
            end
            set(utility_key(utility), utility_config)
        end

        # Disables a utility for all packages
        #
        # This both sets the default value for all packages and resets all
        # package-specific values set with {utility_enable_for} and
        # {utility_disable_for}
        #
        # @param [String] utility the utility name (e.g. 'doc' or 'test')
        # @return [void]
        def utility_disable_all(utility)
            reset(utility_key(utility))
            set("#{utility_key(utility)}_default", false)
        end

        # Disables a utility for a specific package
        #
        # Note that if the default for this utility is to be disabled, this is
        # essentially a no-op.
        #
        # @param [String] utility the utility name (e.g. 'doc' or 'test')
        # @param [String] packages the package names
        # @return [void]
        def utility_disable(utility, *packages)
            utility_config = get(utility_key(utility), Hash.new)
            packages.each do |pkg_name|
                utility_config[pkg_name] = false
            end
            set(utility_key(utility), utility_config)
        end

        def merge(conf)
            config.merge!(conf.config)
        end
    end
end

