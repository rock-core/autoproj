require 'autoproj'
require 'autoproj/autobuild'

module Autoproj
    module CLI
        class Base
            include Ops::Tools

            attr_reader :ws

            def initialize(ws = nil)
                @ws = (ws || Workspace.default)
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

            def resolve_user_selection(selected_packages, options = Hash.new)
                if selected_packages.empty?
                    return ws.manifest.default_packages
                end
                selected_packages = selected_packages.to_set

                selected_packages, nonresolved = ws.manifest.
                    expand_package_selection(selected_packages, options)

                # Try to auto-add stuff if nonresolved
                nonresolved.delete_if do |sel|
                    next if !File.directory?(sel)
                    while sel != '/'
                        handler, srcdir = Autoproj.package_handler_for(sel)
                        if handler
                            Autoproj.message "  auto-adding #{srcdir} using the #{handler.gsub(/_package/, '')} package handler"
                            srcdir = File.expand_path(srcdir)
                            relative_to_root = Pathname.new(srcdir).relative_path_from(Pathname.new(ws.root_dir))
                            pkg = ws.in_package_set(ws.manifest.main_package_set, ws.manifest.file) do
                                send(handler, relative_to_root.to_s)
                            end
                            ws.setup_package_directories(pkg)
                            selected_packages.select(sel, pkg.name, weak: true)
                            break(true)
                        end

                        sel = File.dirname(sel)
                    end
                end

                if Autoproj.verbose
                    Autoproj.message "will install #{selected_packages.packages.to_a.sort.join(", ")}"
                end
                return selected_packages, nonresolved
            end

            def resolve_selection(manifest, user_selection, options = Hash.new)
                options = Kernel.validate_options options,
                    checkout_only: true,
                    only_local: false,
                    recursive: true,
                    ignore_non_imported_packages: false

                resolved_selection, _ = resolve_user_selection(user_selection, filter: false)
                if options[:ignore_non_imported_packages]
                    manifest.each_autobuild_package do |pkg|
                        if !File.directory?(pkg.srcdir)
                            manifest.ignore_package(pkg.name)
                        end
                    end
                end
                resolved_selection.filter_excluded_and_ignored_packages(manifest)

                ops = Ops::Import.new(ws)
                source_packages, osdep_packages = ops.import_packages(
                    resolved_selection,
                    checkout_only: options[:checkout_only],
                    only_local: options[:only_local],
                    recursive: options[:recursive],
                    warn_about_ignored_packages: false)

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
                    color: TTY::Screen.color?,
                    progress: TTY::Screen.color?,
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

                return args, remaining
            end
        end
    end
end

