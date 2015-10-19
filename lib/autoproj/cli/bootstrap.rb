require 'autoproj'
require 'autoproj/cli/base'
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
                args, options = Base.validate_options(args, options)
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
            
            def run(buildconf_info, options)
                ws = Workspace.new(root_dir)
                ws.setup

                seed_config = options.delete(:seed_config)

                switcher = Ops::MainConfigSwitcher.new(ws)
                begin
                    switcher.bootstrap(buildconf_info, options)
                    if seed_config
                        FileUtils.cp seed_config, File.join(ws.config_dir, 'config.yml')
                    end

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
#{ws.prefix_dir}

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

