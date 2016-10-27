require 'autoproj'
require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Show < InspectionTool
            def run(user_selection, short: false, recursive: false, mainline: false, env: false)
                initialize_and_load(mainline: mainline)
                default_packages = ws.manifest.default_packages

                # Filter out selections that match package set names
                package_set_names, user_selection = user_selection.partition do |name|
                    ws.manifest.find_package_set(name)
                end

                if !user_selection.empty? || package_set_names.empty?
                    source_packages, osdep_packages, * =
                        finalize_setup(user_selection, recursive: recursive, non_imported_packages: :return)
                else
                    source_packages, osdep_packages = Array.new, Array.new
                end

                all_matching_osdeps = osdep_packages.map { |pkg| [pkg, true] }
                user_selection.each do |sel|
                    if !osdep_packages.include?(sel) && ws.os_package_resolver.all_definitions.has_key?(sel)
                        all_matching_osdeps << [sel, false]
                    end
                end

                if package_set_names.empty? && source_packages.empty? && all_matching_osdeps.empty?
                    Autoproj.error "no package set, packages or OS packages match #{user_selection.join(" ")}"
                    return
                elsif !source_packages.empty? || !all_matching_osdeps.empty?
                    load_all_available_package_manifests
                    revdeps = ws.manifest.compute_revdeps
                end

                package_set_names = package_set_names.sort
                source_packages   = source_packages.sort
                all_matching_osdeps = all_matching_osdeps.sort_by { |name, _| name }

                if short
                    package_set_names.each do |name|
                        puts "pkg_set #{name}"
                    end
                    source_packages.each do |name|
                        puts "pkg     #{name}"
                    end
                    all_matching_osdeps.each do |name, sel|
                        puts "osdep   #{name} (#{sel ? "not selected" : "selected"})"
                    end
                else
                    package_set_names.each do |pkg_set_name|
                        display_package_set(pkg_set_name)
                    end
                    source_packages.each do |pkg_name|
                        display_source_package(pkg_name, default_packages, revdeps, env: env)
                    end
                    all_matching_osdeps.each do |pkg_name, selected|
                        display_osdep_package(pkg_name, default_packages, revdeps, selected)
                    end
                end
            end

            def display_package_set(name, package_per_line: 8)
                puts Autoproj.color("package set #{name}", :bold)
                pkg_set = ws.manifest.find_package_set(name)
                if !File.directory?(pkg_set.raw_local_dir)
                    puts Autobuild.color("  this package set is not checked out", :magenta)
                end
                if overrides_key = pkg_set.vcs.overrides_key
                    puts "  overrides key: pkg_set:#{overrides_key}"
                end
                if pkg_set.raw_local_dir != pkg_set.user_local_dir
                    puts "  checkout dir: #{pkg_set.raw_local_dir}"
                    puts "  symlinked to: #{pkg_set.user_local_dir}"
                else
                    puts "  path: #{pkg_set.raw_local_dir}"
                end

                puts "  version control information:"
                display_vcs(pkg_set.vcs)

                metapackage = ws.manifest.find_metapackage(name)
                size = metapackage.size
                if size == 0
                    puts "  does not have any packages"
                else
                    puts "  refers to #{metapackage.size} package#{'s' if metapackage.size > 1}"
                end
                names = metapackage.each_package.map(&:name).sort
                package_lines = names.each_slice(package_per_line).map do |*line_names|
                    line_names.join(", ")
                end
                puts "    " + package_lines.join(",\n    ")

            end

            def display_source_package(pkg_name, default_packages, revdeps, options = Hash.new)
                puts Autoproj.color("source package #{pkg_name}", :bold)
                pkg = ws.manifest.find_autobuild_package(pkg_name)
                if !File.directory?(pkg.srcdir)
                    puts Autobuild.color("  this package is not checked out yet, the dependency information will probably be incomplete", :magenta)
                end
                puts "  source definition"
                ws.manifest.load_package_manifest(pkg_name)
                vcs = ws.manifest.find_package_definition(pkg_name).vcs

                display_vcs(vcs)
                display_common_information(pkg_name, default_packages, revdeps)

                puts "  directly depends on: #{pkg.dependencies.sort.join(", ")}"
                puts "  optionally depends on: #{pkg.optional_dependencies.sort.join(", ")}"
                puts "  dependencies on OS packages: #{pkg.os_packages.sort.join(", ")}"
                if options[:env]
                    puts "  environment"
                    pkg.resolved_env.sort_by(&:first).each do |name, v|
                        values = v.split(File::PATH_SEPARATOR)
                        if values.size == 1
                            puts "    #{name}: #{values.first}"
                        else
                            puts "    #{name}:"
                            values.each do |single_v|
                                puts "      #{single_v}"
                            end
                        end
                    end
                end
            end

            def display_vcs(vcs)
                fragments = []
                if vcs.none?
                    fragments << ["has no VCS definition", []]
                else
                    first = true
                    fragments << [nil, vcs_to_array(vcs)]
                    vcs.raw.each do |entry|
                        entry_name =
                            if entry.package_set && entry.file
                                "#{entry.package_set.name} (#{entry.file})"
                            elsif entry.package_set
                                "#{entry.package_set.name}"
                            elsif entry.file
                                "#{entry.file}"
                            end

                        title = if first
                                    "first match: in #{entry_name}"
                                else "overriden in #{entry_name}"
                                end
                        first = false
                        fragments << [title, vcs_to_array(entry.vcs)]
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
            end

            def display_osdep_package(pkg_name, default_packages, revdeps, selected)
                puts Autoproj.color("the osdep '#{pkg_name}'", :bold)
                begin
                    ws.os_package_resolver.resolve_os_packages([pkg_name]).each do |manager_name, packages|
                        puts "  #{manager_name}: #{packages.map { |*subnames| subnames.join(" ") }.join(", ")}"
                    end
                rescue MissingOSDep => e
                    puts "  #{e.message}"
                end

                if !selected
                    puts "  is present, but won't be used by autoproj for '#{pkg_name}'"
                end

                entries = ws.os_package_resolver.all_definitions[pkg_name]
                puts "  #{entries.inject(0) { |c, (files, _)| c + files.size }} matching entries:"
                entries.each do |files, entry|
                    puts "    in #{files.join(", ")}:"
                    lines = YAML.dump(entry).split("\n")
                    lines[0] = lines[0].gsub(/---\s*/, '')
                    if lines[0].empty?
                        lines.shift
                    end
                    puts "        " + lines.join("\n      ")
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
                ws.manifest.resolve_package_name(from).each do |pkg_type, pkg_name|
                    next if pkg_type != :package

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

                fields = []
                if type
                    fields << ['type', type]
                end
                if url
                    fields << ['url', url]
                end
                fields = fields.concat(options.to_a.sort_by { |k, _| k.to_s })
                fields.map do |key, value|
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
