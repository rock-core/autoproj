module Autoproj
    module CLI
        class MainPlugin < Thor
            namespace 'plugin'

            no_commands do
                def ws
                    @ws ||= Workspace.from_pwd
                end

                def install_plugins
                    ws.load_config
                    ws.update_autoproj(restart_on_update: false)
                end

                def read_plugin_list
                    ws.load_config
                    ws.config.get('plugins', Hash.new)
                end

                def write_plugin_list(plugins)
                    ws.load_config
                    ws.config.set('plugins', plugins)
                    ws.save_config
                end
            end

            desc 'install NAME', 'install or upgrade an autoproj plugin'
            option :version, desc: 'a gem version constraint',
                type: 'string', default: '>= 0'
            option :git, desc: 'checkout a git repository instead of downloading the gem',
                type: 'string'
            option :path, desc: 'use the plugin that is already present on this path',
                type: 'string'
            def install(name)
                require 'autoproj'

                gem_options = Hash.new
                if options[:git] && options[:path]
                    raise ArgumentError, "you can provide only one of --git or --path"
                elsif options[:git]
                    gem_options[:git] = options[:git]
                elsif options[:path]
                    gem_options[:path] = options[:path]
                end

                plugins = read_plugin_list
                updated_plugins = plugins.merge(name => [options[:version], gem_options])
                write_plugin_list(updated_plugins)
                begin
                    install_plugins
                rescue Exception
                    write_plugin_list(plugins)
                    install_plugins
                    raise
                end
            end

            desc 'list', 'list installed plugins'
            def list
                require 'autoproj'
                read_plugin_list.sort_by(&:first).each do |name, (version, options)|
                    args = [version, *options.map { |k, v| "#{k}: \"#{v}\"" }]
                    puts "#{name}: #{args.join(", ")}"
                end
            end

            desc 'remove NAME', 'uninstall a plugin'
            def remove(name)
                require 'autoproj'
                plugins = read_plugin_list
                updated_plugins = plugins.dup
                updated_plugins.delete(name)
                write_plugin_list(updated_plugins)
                install_plugins
            end
        end
    end
end
