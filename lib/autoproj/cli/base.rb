require 'autoproj'
require 'autoproj/autobuild'

module Autoproj
    module CLI
        class Base
            include Ops::Tools

            attr_reader :ws

            def initialize(ws = nil)
                @ws = (ws || Workspace.from_environment)
            end

            def normalize_command_line_package_selection(selection)
                selection = selection.map do |name|
                    if File.directory?(name)
                        File.expand_path(name)
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
                            selected_packages.select(sel, pkg.name, true)
                            break(true)
                        end

                        sel = File.dirname(sel)
                    end
                end

                if Autoproj.verbose
                    Autoproj.message "will install #{selected_packages.packages.to_a.sort.join(", ")}"
                end
                selected_packages
            end

            def validate_user_selection(user_selection, resolved_selection)
                not_matched = user_selection.find_all do |pkg_name|
                    !resolved_selection.has_match_for?(pkg_name)
                end
                if !not_matched.empty?
                    raise ConfigError.new, "autoproj: wrong package selection on command line, cannot find a match for #{not_matched.to_a.sort.join(", ")}"
                end
            end
        end
    end
end

