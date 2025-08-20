module Autoproj
    module Ops
        # Operations that modify the source of the main configuration (bootstrap
        # and switch-config)
        class MainConfigSwitcher
            attr_reader :ws

            def initialize(ws)
                @ws = ws
            end

            # Set of directory entries that are expected to be present in the
            # directory in which the user bootstraps
            #
            # @see check_root_dir_empty
            EXPECTED_ROOT_ENTRIES = [".", "..", "autoproj_bootstrap",
                                     ".autoproj", "bootstrap.sh", ENV_FILENAME].to_set

            def check_root_dir_empty?
                (ENV["AUTOPROJ_NONINTERACTIVE"] != "1") &&
                    (ENV["AUTOPROJ_BOOTSTRAP_IGNORE_NONEMPTY_DIR"] != "1")
            end

            # Verifies that {#root_dir} contains only expected entries, to make
            # sure that the user bootstraps into a new directory
            #
            # If the environment variable AUTOPROJ_BOOTSTRAP_IGNORE_NONEMPTY_DIR
            # is set to 1, the check is skipped
            def check_root_dir_empty
                require "set"
                curdir_entries = Dir.entries(ws.root_dir).map { |p| File.basename(p) }.to_set -
                                 EXPECTED_ROOT_ENTRIES
                return if curdir_entries.empty?

                loop do
                    print "The current directory is not empty, continue bootstrapping anyway ? [yes] "
                    STDOUT.flush
                    answer = STDIN.readline.chomp
                    raise Interrupt, "Interrupted by user" if answer == "no"

                    if answer == "" || answer == "yes"
                        # Set this environment variable since we might restart
                        # autoproj later on.
                        ENV["AUTOPROJ_BOOTSTRAP_IGNORE_NONEMPTY_DIR"] = "1"
                        return
                    else
                        STDOUT.puts "invalid answer. Please answer 'yes' or 'no'"
                        STDOUT.flush
                    end
                end
            end

            # Validates the environment variable AUTOPROJ_CURRENT_ROOT during a
            # bootstrap
            #
            # AUTOPROJ_CURRENT_ROOT must be set to either the new root
            # ({ws.root_dir}) or a root that we are reusing
            #
            # @param [Array<String>] reuse set of autoproj roots that are being reused
            # @raise ConfigError
            def validate_autoproj_current_root(reuse)
                return unless (current_root = ENV["AUTOPROJ_CURRENT_ROOT"])
                return if (current_root == ws.root_dir) || reuse.include?(current_root)

                Autoproj.error "the env.sh from #{ENV['AUTOPROJ_CURRENT_ROOT']} seem to already be sourced"
                Autoproj.error "start a new shell and try to bootstrap again"
                Autoproj.error ""
                Autoproj.error "you are allowed to boostrap from another autoproj installation"
                Autoproj.error "only if you reuse it with the --reuse flag"
                raise Autobuild::Exception, ""
            end

            MAIN_CONFIGURATION_TEMPLATE = File.expand_path(File.join("..", "..", "..", "samples", "autoproj"), File.dirname(__FILE__))

            def bootstrap(buildconf_info,
                check_root_dir_empty: check_root_dir_empty?,
                reuse: Array.new)
                self.check_root_dir_empty if check_root_dir_empty
                validate_autoproj_current_root(reuse)

                ws.config.validate_ruby_executable
                ws.config.set "reused_autoproj_installations", reuse, true
                ws.env.export_env_sh(shell_helpers: ws.config.shell_helpers?)

                # If we are not getting the installation setup from a VCS, copy the template
                # files
                if buildconf_info.empty? || buildconf_info.size == 1
                    FileUtils.cp_r MAIN_CONFIGURATION_TEMPLATE, "autoproj"
                end

                if buildconf_info.size == 1 # the user asks us to download a manifest
                    manifest_url = buildconf_info.first
                    Autoproj.message("autoproj: downloading manifest file #{manifest_url}", :bold)
                    manifest_data =
                        begin open(manifest_url, &:read)
                        rescue
                            # Delete the autoproj directory
                            FileUtils.rm_rf "autoproj"
                            raise ConfigError.new, "cannot read file / URL #{manifest_url}, did you mean 'autoproj bootstrap VCSTYPE #{manifest_url}' ?"
                        end

                    File.open(File.join(ws.config_dir, "manifest"), "w") do |io|
                        io.write(manifest_data)
                    end

                elsif buildconf_info.size >= 2 # is a VCS definition for the manifest itself ...
                    type, url, *vcs_options = *buildconf_info
                    url = VCSDefinition.to_absolute_url(url, ws.root_dir)
                    do_switch_config(false, type, url, *vcs_options)
                end
                ws.env.export_env_sh(shell_helpers: ws.config.shell_helpers?)
                ws.config.save
            end

            def switch_config(*args)
                vcs = ws.manifest.vcs
                if args.first =~ /^(\w+)=/
                    # First argument is an option string, we are simply setting the
                    # options without changing the type/url
                    type = vcs.type
                    url = vcs.url
                else
                    type = args.shift
                    url = args.shift
                end
                options = args

                url = VCSDefinition.to_absolute_url(url, ws.root_dir)

                if vcs.type == type && vcs.url == url
                    vcs = vcs.to_hash
                    options.each do |opt|
                        opt_name, opt_value = opt.split("=")
                        vcs[opt_name.to_sym] = opt_value
                    end
                    # Validate the VCS definition, but save the hash as-is
                    ws.manifest.vcs = VCSDefinition.from_raw(vcs)
                    ws.config.set "manifest_source", vcs.dup, true
                    ws.config.save
                    true

                else
                    # We will have to delete the current autoproj directory. Ask the user.
                    opt = Autoproj::BuildOption.new("delete current config", "boolean",
                                                    Hash[default: "false",
                                                         doc: "delete the current configuration ? (required to switch)"], nil)

                    return unless opt.ask(nil)

                    do_switch_config(true, type, url, *options)
                    ws.config.save
                    false
                end
            end

            # @api private
            def do_switch_config(delete_current, type, url, *options)
                vcs_def = Hash.new
                vcs_def["type"] = type
                vcs_def["url"]  = VCSDefinition.to_absolute_url(url, ws.root_dir)
                options.each do |opt|
                    name, value = opt.split("=")
                    value = Integer(value) if value =~ /^\d+$/

                    vcs_def[name] = value
                end

                vcs = VCSDefinition.from_raw(vcs_def)

                # Install the OS dependencies required for this VCS
                ws.install_os_packages([vcs.type], all: nil)

                # Now check out the actual configuration
                config_dir = File.join(ws.root_dir, "autoproj")
                if delete_current
                    # Find a backup name for it
                    backup_base_name = backup_name = "#{config_dir}.bak"
                    index = 0
                    while File.directory?(backup_name)
                        backup_name = "#{backup_base_name}-#{index}.bak"
                        index += 1
                    end

                    FileUtils.mv config_dir, backup_name
                end

                ops = Ops::Configuration.new(ws)
                ops.update_configuration_repository(
                    vcs,
                    "autoproj main configuration",
                    config_dir
                )

                # If the new tree has a configuration file, load it but override
                # the already known parameters once it is loaded
                current_config = ws.config
                # manifest_source
                ws.load_config
                ws.config.merge(current_config)

                # And now save the options: note that we keep the current option set even
                # though we switched configuration. This is not a problem as undefined
                # options will not be reused
                #
                # TODO: cleanup the options to only keep the relevant ones
                vcs_def = Hash["type" => type, "url" => url]
                options.each do |opt|
                    opt_name, opt_val = opt.split "="
                    vcs_def[opt_name] = opt_val
                end
                # Validate the option hash, just in case
                VCSDefinition.from_raw(vcs_def)
                # Save the new options
                ws.config.set "manifest_source", vcs_def.dup, true
                ws.config.save
            rescue Exception => e
                Autoproj.error "switching configuration failed: #{e.message}"
                if backup_name
                    Autoproj.error "restoring old configuration"
                    FileUtils.rm_rf config_dir if config_dir
                    FileUtils.mv backup_name, config_dir
                end
                raise
            ensure
                FileUtils.rm_rf backup_name if backup_name
            end
        end
    end
end
