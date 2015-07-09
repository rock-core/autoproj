require 'autoproj'
require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Show < InspectionTool
            def run(user_selection, options = Hash.new)
                options = Kernel.validate_options options,
                    mainline: false

                initialize_and_load(mainline: options.delete(:mainline))
                default_packages = ws.manifest.default_packages

                source_packages, osdep_packages, * =
                    finalize_setup(user_selection,
                                   recursive: false,
                                   ignore_non_imported_packages: true)

                if source_packages.empty? && osdep_packages.empty?
                    Autoproj.error "no packages or OS packages match #{user_selection.join(" ")}"
                    return
                end
                load_all_available_package_manifests
                revdeps = ws.manifest.compute_revdeps

                source_packages.each do |pkg_name|
                    display_source_package(pkg_name, default_packages, revdeps)
                end
                osdep_packages.each do |pkg_name|
                    display_osdep_package(pkg_name, default_packages, revdeps)
                end
            end

            def display_source_package(pkg_name, default_packages, revdeps)
                puts Autoproj.color("source package #{pkg_name}", :bold)
                pkg = ws.manifest.find_autobuild_package(pkg_name)
                if !File.directory?(pkg.srcdir)
                    puts Autobuild.color("  this package is not checked out yet, the dependency information will probably be incomplete", :magenta)
                end
                puts "  source definition"
                ws.manifest.load_package_manifest(pkg_name)
                vcs = ws.manifest.find_package(pkg_name).vcs

                fragments = []
                if !vcs
                    fragments << ["has no VCS definition", []]
                elsif vcs.raw
                    first = true
                    fragments << [nil, vcs_to_array(vcs)]
                    vcs.raw.each do |pkg_set, vcs_info|
                        pkg_set = if pkg_set then pkg_set.name
                                  end

                        title = if first
                                    "first match: in #{pkg_set}"
                                else "overriden in #{pkg_set}"
                                end
                        first = false
                        fragments << [title, vcs_to_array(vcs_info)]
                    end
                end
                fragments.each do |title, elements|
                    if title
                        puts "    #{title}"
                        elements.each do |key, value|
                            puts "      #{key}: #{value}"
                        end
                    else
                        elements.each do |key, value|
                            puts "    #{key}: #{value}"
                        end
                    end
                end

                display_common_information(pkg_name, default_packages, revdeps)

                puts "  directly depends on: #{pkg.dependencies.sort.join(", ")}"
                puts "  optionally depends on: #{pkg.optional_dependencies.sort.join(", ")}"
                puts "  dependencies on OS packages: #{pkg.os_packages.sort.join(", ")}"
            end

            def display_osdep_package(pkg_name, default_packages, revdeps)
                puts Autoproj.color("the osdep '#{pkg_name}'", :bold)
                ws.osdeps.resolve_os_dependencies([pkg_name]).each do |manager, packages|
                    puts "  #{manager.names.first}: #{packages.map { |*subnames| subnames.join(" ") }.join(", ")}"
                end

                display_common_information(pkg_name, default_packages, revdeps)
            end

            def display_common_information(pkg_name, default_packages, revdeps)
                if default_packages.include?(pkg_name)
                    layout_selection = default_packages.selection[pkg_name]
                    if layout_selection.include?(pkg_name) && layout_selection.size == 1
                        puts "  is directly selected by the manifest"
                    else
                        layout_selection = layout_selection.dup
                        layout_selection.delete(pkg_name)
                        puts "  is directly selected by the manifest via #{layout_selection.to_a.join(", ")}"
                    end
                else
                    puts "  is not directly selected by the manifest"
                end
                if ws.manifest.ignored?(pkg_name)
                    puts "  is ignored"
                end
                if ws.manifest.excluded?(pkg_name)
                    puts "  is excluded: #{Autoproj.manifest.exclusion_reason(pkg_name)}"
                end

                pkg_revdeps = revdeps[pkg_name].to_a
                all_revdeps = compute_all_revdeps(pkg_revdeps, revdeps)
                if pkg_revdeps.empty?
                    puts "  no reverse dependencies"
                else
                    puts "  direct reverse dependencies: #{pkg_revdeps.sort.join(", ")}"
                    puts "  recursive reverse dependencies: #{all_revdeps.sort.join(", ")}"
                end

                selections = Set.new
                all_revdeps = all_revdeps.to_a.sort
                all_revdeps.each do |revdep_parent_name|
                    if default_packages.include?(revdep_parent_name)
                        selections |= default_packages.selection[revdep_parent_name]
                    end
                end

                if !selections.empty?
                    puts "  selected by way of"
                    selections.each do |root_pkg|
                        paths = find_selection_path(root_pkg, pkg_name)
                        if paths.empty?
                            puts "    FAILED"
                        else
                            paths.sort.uniq.each do |p|
                                puts "    #{p.join(">")}"
                            end
                        end
                    end
                end
            end

            def find_selection_path(from, to)
                if from == to
                    return [[from]]
                end

                all_paths = Array.new
                ws.manifest.resolve_package_set(from).each do |pkg_name|
                    path = if pkg_name == from then []
                           else [pkg_name]
                           end

                    pkg = ws.manifest.find_autobuild_package(pkg_name)
                    pkg.dependencies.each do |dep_pkg_name|
                        if result = find_selection_path(dep_pkg_name, to)
                            all_paths.concat(result.map { |p| path + p })
                        end
                    end
                    if pkg.os_packages.include?(to)
                        all_paths << (path + [to])
                    end
                end

                # Now filter common trailing subpaths
                all_paths = all_paths.sort_by(&:size)
                filtered_paths = Array.new
                while !all_paths.empty?
                    path = all_paths.shift
                    filtered_paths << path
                    size = path.size
                    all_paths.delete_if do |p|
                        p[-size..-1] == path
                    end
                end
                filtered_paths.map { |p| [from] + p }
            end

            def vcs_to_array(vcs)
                if vcs.kind_of?(Hash)
                    options = vcs.dup
                    type = options.delete('type')
                    url  = options.delete('url')
                else 
                    options = vcs.options
                    type = vcs.type
                    url = vcs.url
                end

                value = []
                if type
                    value << ['type', type]
                end
                if url
                    value << ['url', url]
                end
                value = value.concat(options.to_a.sort_by { |k, _| k.to_s })
                value.map do |key, value|
                    if value.respond_to?(:to_str) && File.file?(value) && value =~ /^\//
                        value = Pathname.new(value).relative_path_from(Pathname.new(Autoproj.root_dir))
                    end
                    [key, value]
                end
            end

            def compute_all_revdeps(pkg_revdeps, revdeps)
                pkg_revdeps = pkg_revdeps.dup
                all_revdeps = Array.new
                while !pkg_revdeps.empty?
                    parent_name = pkg_revdeps.shift
                    next if all_revdeps.include?(parent_name)
                    all_revdeps << parent_name
                    pkg_revdeps.concat(revdeps[parent_name].to_a)
                end
                all_revdeps
            end
        end
    end
end
