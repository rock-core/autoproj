require 'autoproj/cli'
require 'autoproj/cli/base'

module Autoproj
    module CLI
        class Update < Base
            def parse_options(args)
                options = Hash[
                    keep_going: false,
                    nice: nil]
                parser = OptionParser.new do |opt|
                    opt.banner = ["autoproj builds", "builds the autoproj workspace"].join("\n")
                end
                common_options(parser)
                selected_packages = parser.parse(args)

                ws.osdeps.silent = Autoproj.silent?
                return selected_packages, options
            end

            def run(selected_packages, options)
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

                ws.load_package_sets(checkout_only: true)
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

                if options[:osdeps]
                    install_vcs_osdeps
                    # Install the osdeps for the version control
                    vcs_to_install = Set.new
                    selected_packages.each do |pkg_name|
                        pkg = ws.manifest.find_package(pkg_name)
                        vcs_to_install << pkg.importer.vcs.type
                    end
                    ws.osdeps.install(
                        vcs_to_install,
                        osdeps_mode: options[:osdeps_mode],
                        upgrade: false)
                end

                all_enabled_packages =
                    Autoproj::CmdLine.import_packages(selected_packages,
                                    workspace: ws,
                                    checkout_only: true,
                                    reset: options[:reset])

                load_all_available_package_manifests
                ws.export_installation_manifest

                if options[:osdeps] && !all_enabled_packages.empty?
                    ws.manifest.install_os_dependencies(
                        all_enabled_packages,
                        osdeps_mode: options[:osdeps_mode],
                        upgrade: false)
                end
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


