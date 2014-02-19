module Autoproj
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
end
