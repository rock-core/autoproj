require 'tty/color'
require 'autoproj'
require 'autoproj/autobuild'

module Autoproj
    module CLI
        class Base
            include Ops::Tools

            # The underlying workspace
            # 
            # @return [Workspace]
            attr_reader :ws

            def initialize(ws = Workspace.default)
                @ws = ws
                @env_sh_updated = nil
            end

            # Normalizes the arguments given by the user on the command line
            #
            # This converts relative paths to full paths, and removes mentions
            # of the configuration directory (as it is handled separately in
            # autoproj)
            #
            # @return [(Array<String>,Boolean)] the normalized arguments that
            #   could e.g. be passed to {#resolve_selection}, as well as whether
            #   the config directory was selected or not
            def normalize_command_line_package_selection(selection)
                selection = selection.map do |name|
                    if File.directory?(name)
                        File.expand_path(name) + "/"
                    else
                        name
                    end
                end

                config_selected = false
                selection.delete_if do |name|
                    if name =~ /^#{Regexp.quote(ws.config_dir)}(?:#{File::SEPARATOR}|$)/ ||
                        name =~ /^#{Regexp.quote(ws.remotes_dir)}(?:#{File::SEPARATOR}|$)/
                        config_selected = true
                    elsif (ws.config_dir + File::SEPARATOR) =~ /^#{Regexp.quote(name)}/
                        config_selected = true
                        false
                    end
                end

                return selection, config_selected
            end

            # Resolve a user-provided selection
            #
            # @param (see expand_package_selection)
            # @return [(PackageSelection,Array<String>)] the resolved selections
            #   and the list of entries in selected_packages that have not been
            #   resolved
            def resolve_user_selection(selected_packages, **options)
                if selected_packages.empty?
                    selection = ws.manifest.default_packages
                    if Autoproj.verbose
                        Autoproj.message "selected packages: #{selection.each_package_name.to_a.sort.join(", ")}"
                    end
                    return selection, []
                end
                selected_packages = selected_packages.to_set

                selected_packages, nonresolved = ws.manifest.
                    expand_package_selection(selected_packages, **options)

                # Try to auto-add stuff if nonresolved
                nonresolved.delete_if do |sel|
                    sel = File.expand_path(sel)
                    next if !File.directory?(sel)
                    while sel != '/'
                        handler, srcdir = Autoproj.package_handler_for(sel)
                        if handler
                            Autoproj.message "  auto-adding #{srcdir} using the #{handler.gsub(/_package/, '')} package handler"
                            srcdir = File.expand_path(srcdir)
                            relative_to_root = Pathname.new(srcdir).relative_path_from(Pathname.new(ws.root_dir))
                            pkg = ws.in_package_set(ws.manifest.main_package_set, ws.manifest.file) do
                                send(handler, relative_to_root.to_s, workspace: ws)
                            end
                            ws.setup_package_directories(pkg)
                            selected_packages.select(sel, pkg.name, weak: true)
                            break(true)
                        end

                        sel = File.dirname(sel)
                    end
                end

                if Autoproj.verbose
                    Autoproj.message "selected packages: #{selected_packages.each_package_name.to_a.sort.join(", ")}"
                end
                return selected_packages, nonresolved
            end

            # Resolves the user-provided selection into the set of packages that
            # should be processed further
            #
            # While {#resolve_user_selection} really only considers packages and
            # strings, this methods takes care of doing recursive resolution of
            # dependencies, as well as splitting the packages into source and
            # osdep packages.
            #
            # It loads the packages in sequence (that's the only way the full
            # selection can be computed), and is therefore responsible for
            # updating the packages if needed (disabled by default)
            #
            # @param [Array<String>] user_selection the selection provided by
            #   the user
            # @param [Boolean] checkout_only if packages should be updated
            #   (false) or only missing packages should be checked out (the
            #   default)
            # @param [Boolean] only_local if the update/checkout operation is
            #   allowed to access the network. If only_local is true but some
            #   packages should be checked out, the update will fail
            # @param [Boolean] recursive whether the resolution should be done
            #   recursively (i.e. dependencies of directly selected packages
            #   should be added) or not
            # @param [Symbol] non_imported_packages whether packages
            #   that are not imported should simply be ignored (:ignore),
            #   returned (:return) or should be checked out (:checkout). Setting
            #   checkout_only to true and this to anything but nil
            #   guarantees in effect that no import operation will take place,
            #   only loading
            # @return [(Array<String>,Array<String>,PackageSelection)] the list
            #   of selected source packages, the list of selected OS packages and
            #   the package selection resolution object
            #
            # @see resolve_user_selection
            def resolve_selection(user_selection, checkout_only: true, only_local: false, recursive: true, non_imported_packages: :ignore, auto_exclude: false)
                resolved_selection, _ = resolve_user_selection(user_selection, filter: false)

                ops = Ops::Import.new(ws)
                source_packages, osdep_packages = ops.import_packages(
                    resolved_selection,
                    checkout_only: checkout_only,
                    only_local: only_local,
                    recursive: recursive,
                    warn_about_ignored_packages: false,
                    non_imported_packages: non_imported_packages,
                    auto_exclude: auto_exclude)

                return source_packages, osdep_packages, resolved_selection
            end

            def validate_user_selection(user_selection, resolved_selection)
                not_matched = user_selection.find_all do |pkg_name|
                    !resolved_selection.has_match_for?(pkg_name)
                end
                if !not_matched.empty?
                    raise ConfigError.new, "autoproj: wrong package selection on command line, cannot find a match for #{not_matched.to_a.sort.join(", ")}"
                end
            end

            def validate_options(args, options)
                self.class.validate_options(args, options)
            end

            def self.validate_options(args, options)
                options, remaining = filter_options options,
                    silent: false,
                    verbose: false,
                    debug: false,
                    color: TTY::Color.color?,
                    progress: TTY::Color.color?,
                    parallel: nil

                Autoproj.silent = options[:silent]
                Autobuild.color = options[:color]
                Autobuild.progress_display_enabled = options[:progress]

                if options[:verbose]
                    Autoproj.verbose  = true
                    Autobuild.verbose = true
                    Rake.application.options.trace = false
                    Autobuild.debug = false
                end

                if options[:debug]
                    Autoproj.verbose  = true
                    Autobuild.verbose = true
                    Rake.application.options.trace = true
                    Autobuild.debug = true
                end


                if level = options[:parallel]
                    Autobuild.parallel_build_level = Integer(level)
                    remaining[:parallel] = Integer(level)
                end

                return args, remaining.to_sym_keys
            end

            def export_env_sh(shell_helpers: ws.config.shell_helpers?)
                @env_sh_updated = ws.export_env_sh(shell_helpers: shell_helpers)
            end

            def notify_env_sh_updated
                return if @env_sh_updated.nil?

                if @env_sh_updated
                    Autoproj.message "  updated: #{ws.root_dir}/#{Autoproj::ENV_FILENAME}", :green
                else
                    Autoproj.message "  left unchanged: #{ws.root_dir}/#{Autoproj::ENV_FILENAME}", :green
                end
            end
        end
    end
end

