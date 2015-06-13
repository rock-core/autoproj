require 'autoproj'
require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Query < InspectionTool
            def run(query_string, options = Hash.new)
                initialize_and_load
                finalize_setup([])
                query = Autoproj::Query.parse_query(query_string.first)

                packages =
                    if options[:search_all]
                        ws.manifest.packages.to_a
                    else
                        ws.manifest.all_selected_packages.map do |pkg_name|
                            [pkg_name, ws.manifest.packages[pkg_name]]
                        end
                    end

                matches = packages.map do |name, pkg_def|
                    if priority = query.match(pkg_def)
                        [priority, name]
                    end
                end.compact

                fields = Hash.new
                matches = matches.sort
                matches.each do |priority, name|
                    pkg = ws.manifest.find_autobuild_package(name)
                    fields['SRCDIR'] = pkg.srcdir
                    fields['PREFIX'] = pkg.prefix
                    fields['NAME'] = name
                    fields['PRIORITY'] = priority

                    value = Autoproj.expand(options[:format] || "$NAME", fields)
                    puts value
                end
            end
        end
    end
end

