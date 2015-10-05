require 'autoproj/ops/install'
require 'autoproj/find_workspace'
module Autoproj
    module CLI
        class Upgrade
            def upgrade_from_v2(installer, options = Hash.new)
                installer.install
            end

            def upgrade_from_v1(installer, options = Hash.new)
                root_dir = installer.root_dir

                # Save a backup of the existing env.sh (if the backup does not
                # already exist) to make it easier for a user to downgrade
                env_backup = File.join(root_dir, 'env.sh-autoproj-v1')
                if !File.file?(env_backup)
                    FileUtils.cp File.join(root_dir, 'env.sh'), env_backup
                end

                # Do an install
                installer.run

                # Copy the current configuration, merging it with the autoproj
                # 2.x attributes
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
                FileUtils.cp_r File.join(root_dir, '.remotes'), File.join(root_dir, '.autoproj', 'remotes')
                # Copy the installation manifest
                FileUtils.cp File.join(root_dir, '.autoproj-installation-manifest'),
                    File.join(root_dir, '.autoproj', 'installation-manifest')

                Autoproj.message "now, open a new console, source env.sh and run"
                Autoproj.message "  autoproj osdeps"
                Autoproj.message "  autoproj envsh"
            end

            def create_installer(root_dir, options = Hash.new)
                installer = Autoproj::Ops::Install.new(root_dir)
                installer.local = options[:local]
                installer.private_bundler  = options[:private_bundler] || options[:private]
                installer.private_autoproj = options[:private_autoproj] || options[:private]
                installer.private_gems     = options[:private_gems] || options[:private]
                if gemfile_path = options[:gemfile]
                    installer.gemfile = File.read(gemfile_path)
                end
                installer
            end

            def run(options = Hash.new)
                root_dir = Autoproj.find_v2_workspace_dir
                if root_dir && File.directory?(File.join(root_dir, '.autoproj'))
                    installer = create_installer(root_dir, options)
                    return upgrade_from_v2(installer, options)
                end

                root_dir = Autoproj.find_v1_workspace_dir
                if root_dir && File.directory?(File.join(root_dir, '.gems'))
                    installer = create_installer(root_dir, options)
                    return upgrade_from_v1(installer, options)
                end
            end
        end
    end
end

