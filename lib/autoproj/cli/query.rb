require 'autoproj'
require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Query < InspectionTool
            def run(query_string, options = Hash.new)
                initialize_and_load
                all_selected_packages, * = finalize_setup([])
                all_selected_packages = all_selected_packages.to_set

                query =
                    if !query_string.empty?
                        Autoproj::Query.parse_query(query_string.first)
                    end

                if options[:search_all]
                    packages = ws.manifest.packages.to_a
                else
                    packages = all_selected_packages.map do |pkg_name|
                        [pkg_name, ws.manifest.find_package_definition(pkg_name)]
                    end
                    packages += ws.manifest.all_selected_source_packages.map do |pkg_name|
                        if !all_selected_packages.include?(pkg_name)
                            [pkg_name, ws.manifest.find_package_definition(pkg_name)]
                        end
                    end.compact
                end

                if options[:only_present]
                    packages = packages.find_all do |_, pkg|
                        File.directory?(pkg.autobuild.srcdir)
                    end
                end

                if !query
                    matches = packages.map { |name, _| [0, name] }
                else
                    matches = packages.map do |name, pkg_def|
                        if priority = query.match(pkg_def)
                            [priority, name]
                        end
                    end.compact
                end

                fields = Hash.new
                matches = matches.sort
                matches.each do |priority, name|
                    pkg_def = ws.manifest.find_package_definition(name)
                    pkg = ws.manifest.find_autobuild_package(name)
                    fields['SRCDIR'] = pkg.srcdir
                    fields['PREFIX'] = pkg.prefix
                    fields['NAME'] = name
                    fields['PRIORITY'] = priority
                    fields['URL'] = (pkg_def.vcs.url if pkg_def.vcs)
                    fields['PRESENT'] = File.directory?(pkg.srcdir)

                    value = Autoproj.expand(options[:format] || "$NAME", fields)
                    puts value
                end
            end
        end
    end
end

