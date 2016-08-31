require 'autoproj/cli'
require 'autoproj/cli/base'
require 'autoproj/ops/import'

module Autoproj
    module CLI
        class Update < Base
            def validate_options(packages, options)
                packages, options = super

                if !options[:osdeps]
                    options[:osdeps_mode] = Array.new
                end

                if from = options[:from]
                    options[:from] = Autoproj::InstallationManifest.from_workspace_root(options[:from])
                end
                ws.os_package_installer.filter_uptodate_packages = options[:osdeps_filter_uptodate]

                if options[:aup] && !options[:all] && packages.empty?
                    packages = ['.']
                end

                if options[:force_reset]
                    options[:reset] = :force
                end

                if mainline = options[:mainline]
                    if mainline == 'mainline' || mainline == 'true'
                        options[:mainline] = true
                    end
                end

                return packages, options
            end

            def run(selected_packages, options)
                ws.manifest.accept_unavailable_osdeps = !options[:osdeps]
                explicit_selection = !selected_packages.empty?
                selected_packages, config_selected =
                    normalize_command_line_package_selection(selected_packages)

                # Autoproj and configuration are updated only if (1) it is
                # explicitely selected or (2) nothing is explicitely selected
                update_autoproj =
                    (options[:autoproj] || (
                        options[:autoproj] != false &&
                        !explicit_selection &&
                        !options[:config] && 
                        !options[:checkout_only])
                    )

                update_config =
                    (options[:config] || config_selected || (
                        options[:config] != false &&
                        !explicit_selection &&
                        !options[:autoproj]))

                update_packages =
                    options[:all] ||
                    (explicit_selection && !selected_packages.empty?) ||
                    (!explicit_selection && !options[:config] && !options[:autoproj])

                ws.setup
                parallel = options[:parallel] || ws.config.parallel_import_level

                ws.autodetect_operating_system(force: true)

                if update_autoproj
                    ws.update_autoproj
                end

                ws.load_package_sets(
                    mainline: options[:mainline],
                    only_local: options[:only_local],
                    checkout_only: !update_config || options[:checkout_only],
                    reset: options[:reset],
                    ignore_errors: options[:keep_going],
                    retry_count: options[:retry_count])
                ws.config.save
                if !update_packages
                    return [], [], true
                end

                ws.setup_all_package_directories
                # Call resolve_user_selection once to auto-add packages
                resolve_user_selection(selected_packages)
                # Now we can finalize and re-resolve the selection since the
                # overrides.rb files might have changed it
                ws.finalize_package_setup
                # Finally, filter out exclusions
                resolved_selected_packages, _ =
                    resolve_user_selection(selected_packages)
                validate_user_selection(selected_packages, resolved_selected_packages)

                if !selected_packages.empty?
                    command_line_selection = resolved_selected_packages.dup
                else
                    command_line_selection = Array.new
                end
                selected_packages = resolved_selected_packages

                if other_root = options[:from]
                    setup_update_from(other_root)
                end

                osdeps_options = Hash[install_only: options[:checkout_only]]
                if options[:osdeps_mode]
                    osdeps_options[:osdeps_mode] = options[:osdeps_mode]
                end

                ops = Autoproj::Ops::Import.new(ws)
                source_packages, osdep_packages = 
                    ops.import_packages(selected_packages,
                                    checkout_only: options[:checkout_only],
                                    only_local: options[:only_local],
                                    reset: options[:reset],
                                    recursive: options[:deps],
                                    ignore_errors: options[:keep_going],
                                    parallel: parallel,
                                    retry_count: options[:retry_count],
                                    install_vcs_packages: (osdeps_options if options[:osdeps]))

                ws.finalize_setup
                ws.export_installation_manifest

                if options[:osdeps] && !osdep_packages.empty?
                    ws.install_os_packages(osdep_packages, **osdeps_options)
                end

                ws.export_env_sh(source_packages)
                Autoproj.message "  updated #{ws.root_dir}/#{Autoproj::ENV_FILENAME}", :green

                return command_line_selection, source_packages, osdep_packages
            end

            def load_all_available_package_manifests
                # Load the manifest for packages that are already present on the
                # file system
                ws.manifest.each_autobuild_package do |pkg|
                    if pkg.checked_out?
                        begin
                            ws.manifest.load_package_manifest(pkg.name)
                        rescue Interrupt
                            raise
                        rescue Exception => e
                            Autoproj.warn "cannot load package manifest for #{pkg.name}: #{e.message}"
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

