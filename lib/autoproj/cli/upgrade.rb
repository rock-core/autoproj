require 'autoproj/ops/install'
module Autoproj
    module CLI
        class Upgrade
            def upgrade_from_v2(root_dir)
                installer = Autoproj::Ops::Install.new(root_dir)
                installer.install
            end

            def upgrade_from_v1(root_dir)
                # Do an install
                installer = Autoproj::Ops::Install.new(root_dir)
                installer.run
                # Copy the current configuration
                current_config = File.open(File.join(root_dir, 'autoproj', 'config.yml')) do |io|
                    YAML.load(io)
                end

                config_file_path = File.join(root_dir, '.autoproj', 'config.yml')
                new_config = File.open(config_file_path) do |io|
                    YAML.load(io)
                end
                File.open(config_file_path, 'w') do |io|
                    io.write YAML.dump(current_config.merge(new_config))
                end
                # Copy the remotes symlinks
                FileUtils.mv File.join(root_dir, '.remotes'), File.join(root_dir, '.autoproj', 'remotes')

                Autoproj.message "now, open a new console, source env.sh and run"
                Autoproj.message "  autoproj osdeps"
                Autoproj.message "  autoproj envsh"
            end

            def run(*args)
                root_dir = Workspace.find_workspace_dir
                    if root_dir && File.directory?(File.join(root_dir, '.autoproj'))
                    return upgrade_from_v2(root_dir)
                end

                root_dir = Workspace.find_v1_workspace_dir(ENV['AUTOPROJ_CURRENT_ROOT'] || Dir.pwd)
                if root_dir && File.directory?(File.join(root_dir, '.gems'))
                    return upgrade_from_v1(root_dir)
                end
            end
        end
    end
end

