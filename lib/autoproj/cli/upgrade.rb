module Autoproj
    module CLI
        class Upgrade
            def initialize(root_dir)
                @root_dir = root_dir
            end

            def upgrade_from_v2
                require 'autoproj/ops/install'
                installer = Autoproj::Ops::Install.new(root_dir)
                installer.install
            end

            def find_v1_root_dir(base_dir = ENV['AUTOPROJ_CURRENT_ROOT'] || Dir.pwd)
                path = Pathname.new(base_dir)
                while !path.root?
                    if (path + "autoproj").exist?
                        break
                    end
                    path = path.parent
                end

                if path.root?
                    return
                end

                # I don't know if this is still useful or not ... but it does not hurt
                #
                # Preventing backslashed in path, that might be confusing on some path compares
                if Autobuild.windows?
                    result = result.gsub(/\\/,'/')
                end
                result
            end

            def upgrade_from_v1
                # Do an install
                require 'autoproj/ops/install'
                installer = Autoproj::Ops::Install.new(root_dir)
                installer.run
                # Copy the current configuration
                current_config = File.open(File.join(root_dir, 'autoproj', 'config.yml')) do |io|
                    YAML.load(io)
                end
                new_config = File.open(config_file_path) do |io|
                    YAML.load(io)
                end
                File.open(config_file_path, 'w') do |io|
                    io.write YAML.dump(current_config.merge(new_config))
                end

                Autoproj.message "now, open a new console, source env.sh and run"
                Autoproj.message "  autoproj osdeps"
                Autoproj.message "  autoproj envsh"
            end

            def run(*args)
                root_dir = Workspace.find_root_dir
                if root_dir && File.directory?(File.join(root_dir, '.autoproj'))
                    return upgrade_from_v2
                end

                root_dir = find_v1_root_dir
                if root_dir && File.directory?(root_dir, '.gems')
                    return upgrade_from_v1
                end
            end
        end
    end
end

