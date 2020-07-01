require 'autoproj/cli'
require 'autoproj/cli/base'
require 'autoproj/cli/status'
require 'autoproj/ops/import'

module Autoproj
    module CLI
        class Update < Base
            def validate_options(selection, options)
                selection, options = super

                if from = options[:from]
                    options[:from] = Autoproj::InstallationManifest.from_workspace_root(from)
                end

                if options[:no_deps_shortcut]
                    options[:deps] = false
                end

                if options[:aup] && !options[:config] && !options[:all] && selection.empty?
                    if Dir.pwd == ws.root_dir
                        options[:all] = true
                    else
                        selection = [Dir.pwd]
                    end
                end

                if options.delete(:force_reset)
                    options[:reset] = :force
                end

                if mainline = options[:mainline]
                    if mainline == 'mainline' || mainline == 'true'
                        options[:mainline] = true
                    end
                end

                has_explicit_selection = !selection.empty?
                selection, config_selected =
                    normalize_command_line_package_selection(selection)

                # Autoproj and configuration are updated only if (1) it is
                # explicitely selected or (2) nothing is explicitely selected
                update_autoproj =
                    (options[:autoproj] || (
                        options[:autoproj] != false &&
                        !has_explicit_selection &&
                        !options[:config] &&
                        !options[:checkout_only])
                    )

                update_config =
                    (options[:config] || config_selected || (
                        options[:config] != false &&
                        !has_explicit_selection &&
                        !options[:autoproj]))

                update_packages =
                    options[:all] ||
                    (has_explicit_selection && !selection.empty?) ||
                    (!has_explicit_selection && !options[:config] && !options[:autoproj])

                options[:bundler] = update_autoproj
                options[:autoproj] = update_autoproj
                options[:config]   = update_config
                options[:packages] = update_packages
                return selection, options
            end

            def run(selected_packages, run_hook: false, report: true, ask: false, **options)
                ws.manifest.accept_unavailable_osdeps = !options[:osdeps]
                ws.setup
                ws.autodetect_operating_system(force: true)

                if ask
                    prompt = TTY::Prompt.new
                    options[:bundler] &&= prompt.yes?("Update bundler ?")
                    options[:autoproj] &&= prompt.yes?("Update autoproj ?")
                end

                ws.update_bundler if options[:bundler]
                ws.update_autoproj if options[:autoproj]

                begin
                    ws.load_package_sets(
                        mainline: options[:mainline],
                        only_local: options[:only_local],
                        checkout_only: !options[:config] || options[:checkout_only],
                        reset: options[:reset],
                        keep_going: options[:keep_going],
                        retry_count: options[:retry_count]
                    )
                rescue ImportFailed => configuration_import_failure
                    if !options[:keep_going]
                        raise
                    end
                ensure
                    ws.config.save
                end

                if options[:packages]
                    command_line_selection, selected_packages =
                        finish_loading_configuration(selected_packages)
                else
                    ws.setup_all_package_directories
                    ws.finalize_package_setup
                    command_line_selection, selected_packages = [], PackageSelection.new
                end

                osdeps_options = normalize_osdeps_options(
                    checkout_only: options[:checkout_only],
                    osdeps_mode: options[:osdeps_mode],
                    osdeps: options[:osdeps],
                    osdeps_filter_uptodate: options[:osdeps_filter_uptodate])

                source_packages, osdep_packages, import_failure =
                    update_packages(
                        selected_packages,
                        osdeps: options[:osdeps],
                        osdeps_options: osdeps_options,
                        from: options[:from],
                        checkout_only: options[:checkout_only],
                        only_local: options[:only_local],
                        reset: options[:reset],
                        deps: options[:deps],
                        keep_going: options[:keep_going],
                        parallel: options[:parallel] || ws.config.parallel_import_level,
                        retry_count: options[:retry_count],
                        auto_exclude: options[:auto_exclude],
                        ask: ask,
                        report: report)

                ws.finalize_setup
                ws.export_installation_manifest

                if options[:osdeps] && !osdep_packages.empty?
                    ws.install_os_repositories
                    ws.install_os_packages(osdep_packages, **osdeps_options)
                end

                if run_hook
                    if options[:osdeps]
                        CLI::Main.run_post_command_hook(:update, ws,
                            source_packages: source_packages,
                            osdep_packages: osdep_packages)
                    else
                        CLI::Main.run_post_command_hook(:update, ws,
                            source_packages: source_packages,
                            osdep_packages: [])
                    end
                end

                export_env_sh

                if !options[:auto_exclude] && !options[:ignore_errors]
                    if import_failure && configuration_import_failure
                        raise ImportFailed.new(configuration_import_failure.original_errors + import_failure.original_errors)
                    elsif import_failure
                        raise import_failure
                    elsif configuration_import_failure
                        raise configuration_import_failure
                    end
                end

                return command_line_selection, source_packages, osdep_packages
            end

            def finish_loading_configuration(selected_packages)
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
                return command_line_selection, resolved_selected_packages
            end

            def normalize_osdeps_options(
                checkout_only: false, osdeps: true, osdeps_mode: nil,
                osdeps_filter_uptodate: true)

                osdeps_options = Hash[install_only: checkout_only]
                if osdeps_mode
                    osdeps_options[:osdeps_mode] = osdeps_mode
                elsif !osdeps
                    osdeps_options[:osdeps_mode] = Array.new
                end
                ws.os_package_installer.filter_uptodate_packages = osdeps_filter_uptodate
                osdeps_options
            end

            class AskUpdateFilter
                def initialize(prompt, parallel: 1, only_local: false)
                    @prompt = prompt
                    @only_local = only_local
                    @executor = Concurrent::FixedThreadPool.new(parallel, max_length: 0)

                    @parallel = parallel
                    @futures = {}
                    @lookahead_queue = []
                end

                def call(pkg)
                    unless (status = @futures.delete(pkg).value)
                        raise v.reason
                    end

                    clean = !status.unexpected &&
                            (status.sync || (status.local && !status.remote))
                    if clean
                        msg = Autobuild.color('already up-to-date', :green)
                        pkg.autobuild.message "#{msg} %s"
                        return false
                    end

                    Autobuild.progress_display_synchronize do
                        status.msg.each { |m| puts m }
                        @prompt.yes?("Update #{pkg.name} ?")
                    end
                end

                def lookahead(pkg)
                    @futures[pkg] = Concurrent::Future.execute(executor: @executor) do
                        Status.status_of_package(
                            pkg, snapshot: false, only_local: @only_local
                        )
                    end
                end
            end

            def update_packages(selected_packages,
                from: nil, checkout_only: false, only_local: false, reset: false,
                deps: true, keep_going: false, parallel: 1,
                retry_count: 0, osdeps: true, auto_exclude: false, osdeps_options: Hash.new,
                report: true, ask: false)

                setup_update_from(from) if from

                filter =
                    if ask
                        prompt = TTY::Prompt.new
                        filter = AskUpdateFilter.new(
                            prompt, parallel: parallel, only_local: only_local
                        )
                    else
                        ->(pkg) { true }
                    end

                ops = Autoproj::Ops::Import.new(
                    ws, report_path: (ws.import_report_path if report))
                source_packages, osdep_packages =
                        ops.import_packages(selected_packages,
                                        checkout_only: checkout_only,
                                        only_local: only_local,
                                        reset: reset,
                                        recursive: deps,
                                        keep_going: keep_going,
                                        parallel: parallel,
                                        retry_count: retry_count,
                                        install_vcs_packages: (osdeps_options if osdeps),
                                        auto_exclude: auto_exclude,
                                        filter: filter)
                [source_packages, osdep_packages, nil]
            rescue ExcludedSelection => e
                raise CLIInvalidSelection, e.message, e.backtrace
            rescue PackageImportFailed => import_failure
                raise unless keep_going

                [import_failure.source_packages,
                 import_failure.osdep_packages,
                 import_failure]
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

