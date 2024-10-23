require "backports/2.4.0/float/dup"
require "backports/2.4.0/fixnum/dup"
require "backports/2.4.0/nil_class/dup"
require "backports/2.4.0/false_class/dup"
require "backports/2.4.0/true_class/dup"

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
        # Whether the configuration should be performed interactively
        # or not
        attr_accessor :interactive

        def initialize(path = nil)
            @config = Hash.new
            @overrides = Hash.new
            @declared_options = Hash.new
            @displayed_options = Hash.new
            @path = path
            @modified = false
        end

        # Whether the configuration was changed since the last call to {#load}
        # or {#save}
        def modified?
            @modified
        end

        # Resets the modified? flag to false
        def reset_modified
            @modified = false
        end

        # Deletes the current configuration for all options or the one specified
        #
        # The user will be asked for a new value next time one of the reset
        # options is needed
        #
        # @param [String] name the option name (or by default nil to reset all
        #   options)
        # @return the deleted value
        def reset(name = nil)
            if name
                @modified ||= config.has_key?(name)
                config.delete(name)
                overrides.delete(name)
            else
                @config.clear
                @overrides.clear
                @modified = true
            end
        end

        # Sets a configuration option
        #
        # @param [String] key the option name
        # @param [Object] value the option value
        # @param [Boolean] user_validated if true, autoproj will not ask the
        #   user about this value next time it is needed. Otherwise, it will be
        #   asked about it, the new value being used as default
        def set(key, value, user_validated = false)
            if config.has_key?(key)
                @modified ||= (config[key][0] != value)
            else
                @modified = true
            end
            config[key] = [value.dup, user_validated]
        end

        # Override a known option value
        #
        # The new value will not be saved to disk, unlike with {set}
        def override(option_name, value)
            overrides[option_name] = value
        end

        # Remove all overrides
        def reset_overrides(*names)
            if names.empty?
                @overrides.clear
            else
                names.each { |n| @overrides.delete(n) }
            end
        end

        # Tests whether a value is set for the given option name
        #
        # @return [Boolean]
        def has_value_for?(name)
            config.has_key?(name) || overrides.has_key?(name)
        end

        # Get the value for a given option
        def get(key, *default_value)
            return overrides[key].dup if overrides.has_key?(key)

            has_value = config.has_key?(key)
            value, validated = config[key]

            if !declared?(key)
                if has_value
                    value.dup
                elsif default_value.empty?
                    raise ConfigError, "undeclared option '#{key}'"
                else
                    default_value.first.dup
                end
            elsif validated
                doc = declared_options[key].short_doc
                doc = "#{doc}:" if doc[-1, 1] != "?"
                displayed_options[key] = value
                value.dup
            else
                configure(key).dup
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
        def declare(name, type, **options, &validator)
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
            if (opt = declared_options[option_name])
                if (current_value = config[option_name])
                    current_value = current_value.first
                end
                is_default = false
                if interactive?
                    value = opt.ask(current_value, nil)
                else
                    value, is_default = opt.ensure_value(current_value)
                    Autoproj.info "       using: #{value} (noninteractive mode)"
                end
                @modified = true
                if is_default
                    value = opt.validate(value)
                else
                    config[option_name] = [value, true]
                    displayed_options[option_name] = value
                end
                value
            else
                raise ConfigError.new, "undeclared option '#{option_name}'"
            end
        end

        def load(path: self.path, reconfigure: false)
            current_keys = @config.keys
            return unless (h = YAML.load(File.read(path)))

            h.each do |key, value|
                current_keys.delete(key)
                set(key, value, !reconfigure)
            end
            @modified = false if current_keys.empty?
        end

        def reconfigure!
            new_config = Hash.new
            config.each do |key, (value, _user_validated)|
                new_config[key] = [value, false]
            end
            @modified = true
            @config = new_config
        end

        def save(path = self.path, force: false)
            return if !modified? && !force

            Ops.atomic_write(path) do |io|
                h = Hash.new
                config.each do |key, value|
                    h[key] = value.first
                end

                io.write YAML.dump(h)
            end
            @modified = false
        end

        def each_reused_autoproj_installation(&block)
            if has_value_for?("reused_autoproj_installations")
                get("reused_autoproj_installations").each(&block)
            else
                [].each(&block)
            end
        end

        def import_log_enabled?
            get("import_log_enabled", true)
        end

        def import_log_enabled=(value)
            set("import_log_enabled", !!value)
        end

        def parallel_build_level
            get("parallel_build_level", nil) || Autobuild.parallel_build_level
        end

        def parallel_build_level=(level)
            set("parallel_build_level", level)
            Autobuild.parallel_build_level = level
        end

        def parallel_import_level
            get("parallel_import_level", 10)
        end

        def parallel_import_level=(level)
            set("parallel_import_level", level)
        end

        # The Ruby platform and version-specific subdirectory used by bundler and rubygem
        def self.gems_path_suffix
            Ops::Install.gems_path_suffix
        end

        # The gem install root into which the workspace gems are installed
        #
        # Note that while this setting is separated from the other gems path,
        # the only way to reliably isolate the gems of an autoproj workspace is
        # to separate both the autoproj gems and the workspace gems. This is why
        # there are only --public and --private settings in autoproj_install
        #
        # The gems are actually installed under a platform and version-specific
        # subdirectory (returned by {#gems_path_suffix})
        #
        # @param [Workspace] ws the workspace whose gems are being considered
        # @return [String]
        def gems_install_path
            get("gems_install_path")
        end

        # The GEM_HOME into which the workspace gems are installed
        #
        # @param [Workspace] ws the workspace whose gems are being considered
        # @return [String]
        def gems_gem_home
            File.join(gems_install_path, self.class.gems_path_suffix)
        end

        # The full path to the expected ruby executable
        def ruby_executable
            unless (path = get("ruby_executable", nil))
                path = OSPackageResolver.autodetect_ruby_program
                set("ruby_executable", path, true)
            end

            path
        end

        # Verify that the Ruby executable that is being used to run autoproj
        # matches the one expected in the configuration
        def validate_ruby_executable
            actual = OSPackageResolver.autodetect_ruby_program
            if has_value_for?("ruby_executable")
                expected = get("ruby_executable")
                if expected != actual
                    raise ConfigError.new, "this autoproj installation was bootstrapped using #{expected}, but you are currently running under #{actual}. Changing the Ruby executable for in an existing autoproj workspace is unsupported"
                end
            else
                set("ruby_executable", actual, true)
            end
        end

        def use_prerelease?
            use_prerelease =
                if (env_flag = ENV["AUTOPROJ_USE_PRERELEASE"])
                    env_flag == "1"
                elsif has_value_for?("autoproj_use_prerelease")
                    get("autoproj_use_prerelease")
                end
            set "autoproj_use_prerelease", (use_prerelease ? true : false), true
            use_prerelease
        end

        def shell_helpers?
            get "shell_helpers", true
        end

        def shell_helpers=(flag)
            set "shell_helpers", flag, true
        end

        def bundler_version
            get "bundler_version", nil
        end

        def apply_autobuild_configuration
            if has_value_for?("autobuild")
                params = get("autobuild")
                if params.kind_of?(Hash)
                    params.each do |k, v|
                        Autobuild.send("#{k}=", v)
                    end
                end
            end
        end

        # A cache directory for autobuild's importers
        def importer_cache_dir
            get("importer_cache_dir", nil)
        end

        # Set import and gem cache directory
        def importer_cache_dir=(path)
            set("importer_cache_dir", path, true)
        end

        # Sets the directory in which packages will be installed
        def prefix_dir=(path)
            set("prefix", path, true)
        end

        # Whether Autoproj should warn if a package set overrides the osdep of
        # another
        #
        # It is true for historical reasons. Set this to false in your
        # workspace's init.rb for the new behavior
        #
        # @see osdeps_warn_overrides=
        def osdeps_warn_overrides?
            get "osdeps_warn_overrides", true
        end

        # Sets whether Autoproj should warn if a package set overrides the osdep
        # of another
        #
        # It is true for historical reasons. Set this to false in your
        # workspace's init.rb for the new behavior
        #
        # @see osdeps_warn_overrides?
        def osdeps_warn_overrides=(flag)
            set "osdeps_warn_overrides", flag
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
            get("prefix", "install")
        end

        # Sets the shells used in this workspace.
        def user_shells=(shells)
            set("user_shells", shells, true)
        end

        # The shells used in this workspace.
        #
        # @return [Array<String>]
        def user_shells
            get("user_shells", [])
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
            get("build", "build")
        end

        # Defines a folder to which source packages will be layed out relative to
        #
        # If nil, packages will be layed out relative to root_dir
        # Only relative paths are allowed
        #
        # The default is nil
        #
        # @return [String,nil]
        def source_dir
            get("source", nil)
        end

        # Returns true if there should be one prefix per package
        #
        # The default is false (disabled)
        #
        # @return [Boolean]
        def separate_prefixes?
            get("separate_prefixes", false)
        end

        # Controls whether there should be one prefix per package
        #
        # @see separate_prefixes?
        def separate_prefixes=(flag)
            set("separate_prefixes", flag, true)
        end

        # Returns true if packages and prefixes should be auto-generated, based
        # on the SHA of the package names. This is meant to be used for build
        # services that want to check that dependencies are properly set
        #
        # The default is false (disabled)
        #
        # @return [Boolean]
        def randomize_layout?
            get("randomize_layout", false)
        end

        # Sets whether the layout should be randomized
        #
        # @return [Boolean]
        # @see randomize_layout?
        def randomize_layout=(value)
            set("randomize_layout", value, true)
        end

        # Returns true if the configuration should be performed interactively
        #
        # @return [Boolean]
        # @see interactive=
        def interactive?
            if !interactive.nil?
                return interactive
            elsif ENV["AUTOPROJ_NONINTERACTIVE"] == "1"
                return false
            elsif has_value_for?("interactive")
                return get("interactive")
            end

            true
        end

        DEFAULT_UTILITY_SETUP = Hash[
            "doc" => true,
            "test" => false]

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
            else
                get("#{utility_key(utility)}_default", DEFAULT_UTILITY_SETUP[utility])
            end
        end

        # Set the given utility to enabled by default
        #
        # Unlike {#utility_enable_all} and {#utility_disable_all}, it does
        # not touch existing exclusions
        #
        # @param [String] utility the utility name (e.g. 'doc' or 'test')
        # @param [Boolean] enabled whether the utility will be enabled (true) or
        #   disabled (false)
        # @return [void]
        def utility_default(utility, enabled)
            set("#{utility_key(utility)}_default", enabled ? true : false)
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

        # Whether the OS package handler should prefer installing OS-independent
        # packages (as e.g. RubyGems) as opposed to the binary packages
        # equivalent (e.g. thor as a gem vs. thor as the ruby-thor Ubuntu
        # package)
        #
        # This is false by default
        def prefer_indep_over_os_packages?
            get("prefer_indep_over_os_packages", false)
        end

        # The configuration as a key => value map
        def to_hash
            result = Hash.new
            @config.each do |key, (value, _)|
                if declared_options.include?(key)
                    result[key] = declared_options[key].ensure_value(value)
                else
                    result[key] = value
                end
            end
            overrides.each do |key, value|
                result[key] = value
            end
            result
        end

        # Allows to load a seed-config.yml file (also from a buildconf repository)
        # rather than providing it before checkout using the --seed-config paramater
        # of the autoproj_bootstrap script
        # this allows to bootstrap with --no-interactive and still apply a custom config e.g. in CI/CD
        # The call to this function has to be in the init.rb of the buildconf BEFORE any other
        # config option, e.g. the git server configuration settings
        # The filename parameter is the name of the config seed yml file in the repository
        def load_config_once(filename, config_dir: Autoproj.workspace.config_dir)
            seed_config = File.expand_path(filename, config_dir)

            return if get("default_config_applied_#{seed_config}", false)

            Autoproj.message "loading seed config #{seed_config}"
            load path: seed_config
            set "default_config_applied_#{seed_config}", true, true
        end

        # Similar to load_config_once but asks the user if the default config should be applied
        def load_config_once_with_permission(filename, default: "yes", config_dir: Autoproj.workspace.config_dir)
            seed_config = File.expand_path(filename, config_dir)
            # only run this code if config has not beed applied already (don't run when reconfiguring)
            return if has_value_for?("use_default_config_#{seed_config}")

            declare "use_default_config_#{seed_config}",
                    "boolean",
                    default: default,
                    doc: ["Should the default workspace config be used?",
                          "This buildconf denines a default configuration in the buildconf (#{seed_config})",
                          "Should it be applied?"]
            if get("use_default_config_#{seed_config}")
                load_config_once(filename, config_dir: config_dir)
            end
        end
    end
end
