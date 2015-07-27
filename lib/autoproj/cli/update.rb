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
                    options[:from] = Autoproj::InstallationManifest.from_root(options[:from])
                end
                ws.osdeps.filter_uptodate_packages = options[:osdeps_filter_uptodate]

                if options[:aup] && !options[:all] && packages.empty?
                    packages = ['.']
                end

                if options[:autoproj].nil?
                    options[:autoproj] = packages.empty?
                end

                return packages, options
            end

            def run(selected_packages, options)
                selected_packages, config_selected =
                    normalize_command_line_package_selection(selected_packages)

                if options[:config].nil?
                    options[:config] = selected_packages.empty? || config_selected
                end

                ws.setup

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
                    only_local: options[:local],
                    checkout_only: !options[:config] || options[:checkout_only],
                    ignore_errors: options[:keep_going])
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

                if options[:osdeps]
                    # Install the osdeps for the version control
                    vcs_to_install = Set.new
                    selected_packages.each_source_package_name do |pkg_name|
                        if pkg = ws.manifest.find_package(pkg_name)
                            if pkg.vcs
                                vcs_to_install << pkg.vcs.type
                            end
                        else
                            raise "cannot find package #{pkg_name}"
                        end
                    end
                    ws.osdeps.install(vcs_to_install, osdeps_options)
                end

                ops = Autoproj::Ops::Import.new(ws)
                source_packages, osdep_packages = 
                    ops.import_packages(selected_packages,
                                    checkout_only: options[:checkout_only],
                                    only_local: options[:local],
                                    reset: options[:reset],
                                    recursive: options[:deps],
                                    ignore_errors: options[:keep_going])

                ws.finalize_setup
                ws.export_installation_manifest

                if options[:osdeps] && !osdep_packages.empty?
                    ws.osdeps.install(osdep_packages, osdeps_options)
                end

                ws.export_env_sh(source_packages)
                Autoproj.message "  updated #{ws.root_dir}/#{Autoproj::ENV_FILENAME}", :green

                return command_line_selection, source_packages, osdep_packages
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

