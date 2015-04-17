require 'autoproj/cli'
require 'autoproj/cli/base'
require 'autoproj/ops/import'

module Autoproj
    module CLI
        class Update < Base
            def parse_aup_options(args)
                parse_options(args, true)
            end

            def parse_options(args, aup = false)
                options = Hash[
                    config: nil,
                    autoproj: nil,
                    osdeps: true,
                    keep_going: false,
                    update_from: nil,
                    checkout_only: false,
                    local: false,
                    nice: nil]

                build_all = false
                parser = OptionParser.new do |opt|
                    if aup
                        opt.banner = ["aup", "updates packages within the autoproj workspace"].join("\n")
                        build_all = false
                        opt.on '--all', 'build the whole workspace instead of only the current package and its dependencies' do
                            build_all = true
                        end
                    else
                        opt.banner = ["autoproj update", "updates packages within the autoproj workspace"].join("\n")
                    end
                    opt.on "--[no-]config", "(do not) update configuration. The default is to update configuration if explicitely selected or if no additional arguments are given on the command line, and to not do it if packages are explicitely selected on the command line" do |flag|
                        options[:config] = flag
                    end

                    opt.on "--(no-)autoproj", "(do not) update autoproj. This is automatically enabled only if no arguments are given on the command line" do |flag|
                        options[:autoproj] = flag
                    end
                    opt.on "--[no-]osdeps", "enable or disable osdeps handling" do |flag|
                        options[:osdeps] = false
                        if !flag
                            options[:osdeps_mode] = Array.new
                        end
                    end
                    opt.on "--osdeps=NAME[,NAME]", Array, "only update the given osdeps handlers" do |handlers|
                        options[:osdeps_mode] = handlers
                    end
                    opt.on "-k", "--keep-going", "go on updating even in the presence of errors" do
                        options[:keep_going] = true
                    end
                    opt.on('--from PATH', 'use this existing autoproj installation to check out the packages (for importers that support this)') do |path|
                        options[:update_from] = Autoproj::InstallationManifest.from_root(File.expand_path(path))
                    end
                    opt.on("--[no-]update", "Deprecated, use --checkout-only instead") do |flag|
                        options[:checkout_only] = flag
                    end
                    opt.on("-c", "--checkout-only", "only checkout packages, do not update existing ones") do
                        options[:checkout_only] = true
                    end
                    opt.on("--local", "use only local information for the update (for importers that support it)") do
                        options[:local] = true
                    end
                    opt.on('--nice NICE', Integer, 'nice the subprocesses to the given value') do |value|
                        options[:nice] = value
                    end
                    opt.on('--[no-]osdeps-filter-uptodate', 'controls whether the osdeps subsystem should filter up-to-date packages or not') do |flag|
                        ws.osdeps.filter_uptodate_packages = flag
                    end
                    opt.on('--osdeps-mode=MODE', 'override the current osdeps configuration mode') do |forced_mode|
                    end
                end
                common_options(parser)
                selected_packages = parser.parse(args)

                if aup && !build_all && selected_packages.empty?
                    selected_packages << '.'
                end

                if options[:autoproj].nil?
                    options[:autoproj] = selected_packages.empty?
                end

                ws.osdeps.silent = Autoproj.silent?
                return selected_packages, options
            end

            def run(selected_packages, options)
                selected_packages, config_selected =
                    normalize_command_line_package_selection(selected_packages)

                if options[:config].nil?
                    options[:config] = selected_packages.empty? || config_selected
                end

                ws.setup
                ws.install_ruby_shims

                # Do that AFTER we have properly setup ws.osdeps as to avoid
                # unnecessarily redetecting the operating system
                if options[:osdeps]
                    ws.config.set(
                        'operating_system',
                        Autoproj::OSDependencies.operating_system(:force => true),
                        true)
                end

                if options[:autoproj]
                    ws.update_autoproj
                end

                ws.load_package_sets(
                    only_local: options[:only_local],
                    checkout_only: !options[:config] || options[:checkout_only])
                if selected_packages.empty? && config_selected
                    return
                end

                ws.setup_all_package_directories
                # Call resolve_user_selection once to auto-add packages
                resolve_user_selection(selected_packages)
                # Now we can finalize and re-resolve the selection since the
                # overrides.rb files might have changed it
                ws.finalize_package_setup
                # Finally, filter out exclusions
                resolved_selected_packages =
                    resolve_user_selection(selected_packages)
                validate_user_selection(selected_packages, resolved_selected_packages)

                if !selected_packages.empty?
                    command_line_selection = resolved_selected_packages.dup
                else
                    command_line_selection = Array.new
                end
                ws.manifest.explicit_selection = resolved_selected_packages
                selected_packages = resolved_selected_packages

                if other_root = options[:update_from]
                    setup_update_from(other_root)
                end

                osdeps_options = Hash[install_only: options[:checkout_only]]
                if options[:osdeps_mode]
                    osdeps_options[:osdeps_mode] = options[:osdeps_mode]
                end

                if options[:osdeps]
                    # Install the osdeps for the version control
                    vcs_to_install = Set.new
                    selected_packages.each do |pkg_name|
                        pkg = ws.manifest.find_package(pkg_name)
                        vcs_to_install << pkg.vcs.type
                    end
                    ws.osdeps.install(vcs_to_install, osdeps_options)
                end

                ops = Autoproj::Ops::Import.new(ws)
                all_enabled_packages = 
                    ops.import_packages(selected_packages,
                                    workspace: ws,
                                    checkout_only: options[:checkout_only],
                                    only_local: options[:only_local],
                                    reset: options[:reset],
                                    ignore_errors: options[:keep_going])

                load_all_available_package_manifests
                Autoproj::CmdLine.export_installation_manifest

                if options[:osdeps] && !all_enabled_packages.empty?
                    ws.manifest.install_os_dependencies(
                        all_enabled_packages, osdeps_options)
                end

                ws.env.export_env_sh
                Autoproj.message "autoproj: updated #{ws.root_dir}/#{Autoproj::ENV_FILENAME}", :green

                return command_line_selection, all_enabled_packages
            end

            def load_all_available_package_manifests
                # Load the manifest for packages that are already present on the
                # file system
                ws.manifest.packages.each_value do |pkg|
                    if File.directory?(pkg.autobuild.srcdir)
                        begin
                            ws.manifest.load_package_manifest(pkg.autobuild.name)
                        rescue Interrupt
                            raise
                        rescue Exception => e
                            Autoproj.warn "cannot load package manifest for #{pkg.autobuild.name}: #{e.message}"
                        end
                    end
                end
            end

            def setup_update_from(other_root)
                manifest.each_autobuild_package do |pkg|
                    if pkg.importer.respond_to?(:pick_from_autoproj_root)
                        if !pkg.importer.pick_from_autoproj_root(pkg, other_root)
                            pkg.update = false
                        end
                    else
                        pkg.update = false
                    end
                end
            end
        end
    end
end

