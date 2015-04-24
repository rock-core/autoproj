require 'autoproj'
require 'autoproj/ops/tools'
require 'autoproj/ops/main_config_switcher'

module Autoproj
    module CLI
        class Bootstrap
            include Ops::Tools

            attr_reader :root_dir

            def initialize(root_dir = Dir.pwd)
                if File.exists?(File.join(root_dir, 'autoproj', "manifest"))
                    raise ConfigError, "this installation is already bootstrapped. Remove the autoproj directory if it is not the case"
                end
                @root_dir = root_dir
            end

            def validate_options(args, options)
                args, options = super
                if path = options[:reuse]
                    if path == 'reuse'
                        path = ENV['AUTOPROJ_CURRENT_ROOT']
                    end

                    path = File.expand_path(path)
                    if !File.directory?(path) || !File.directory?(File.join(path, 'autoproj'))
                        raise ArgumentError, "#{path} does not look like an autoproj installation"
                    end
                    options[:reuse] = [path]
                end
                return args, options
            end
            
            def restart_if_needed
                # Check if the .autoprojrc changed the PATH and therefore which autoproj script
                # should be executed ... and restart if it did
                autoproj_path = Autobuild.find_in_path('autoproj')
                if $0 != autoproj_path
                    puts "your .autoprojrc file changed PATH in a way that requires the restart of autoproj"

                    if ENV['AUTOPROJ_RESTARTING']
                        puts "infinite loop detected, will not restart this time"
                    else
                        require 'rbconfig'
                        ws.config.save
                        exec(ws.config.ruby_executable, autoproj_path, *ARGV)
                    end
                end
            end

            def install_autoproj_gem_in_new_root(ws)
                # Install the autoproj/autobuild gem explicitely in the new
                # root.
                original_env =
                    Hash['GEM_HOME' => Gem.paths.home,
                         'GEM_PATH' => Gem.paths.path]

                begin
                    Gem.paths =
                        Hash['GEM_HOME' => File.join(root_dir, '.gems'),
                             'GEM_PATH' => []]
                    PackageManagers::GemManager.with_prerelease(ws.config.use_prerelease?) do
                        ws.osdeps.install(%w{autobuild autoproj})
                    end
                ensure
                    Gem.paths = original_env
                end
            end

            def run(buildconf_info, options)
                ws = Workspace.new(root_dir)
                ws.setup
                install_autoproj_gem_in_new_root(ws)
                restart_if_needed

                switcher = Ops::MainConfigSwitcher.new(ws)
                begin
                    switcher.bootstrap(buildconf_info, options)

                    STDERR.puts <<-EOTEXT


#{Autoproj.color('autoproj bootstrap successfully finished', :green, :bold)}

#{Autoproj.color('To further use autoproj and the installed software', :bold)}, you
must add the following line at the bottom of your .bashrc:
source #{root_dir}/#{Autoproj::ENV_FILENAME}

WARNING: autoproj will not work until your restart all
your consoles, or run the following in them:
$ source #{root_dir}/#{Autoproj::ENV_FILENAME}

#{Autoproj.color('To import and build the packages', :bold)}, you can now run
aup
amake

The resulting software is installed in
#{root_dir}/install

                    EOTEXT

                rescue RuntimeError
                    STDERR.puts <<-EOTEXT
#{Autoproj.color('autoproj bootstrap failed', :red, :bold)}
To retry, first source the #{Autoproj::ENV_FILENAME} script with
source #{root_dir}/#{Autoproj::ENV_FILENAME}
and then re-run autoproj bootstrap
autoproj bootstrap '#{ARGV.join("'")}'
                    EOTEXT

                    raise
                end
            end
        end
    end
end

