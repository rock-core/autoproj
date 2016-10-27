require 'autoproj'
require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Query < InspectionTool
            def find_all_matches(query, packages)
                matches = packages.map do |pkg|
                    if priority = query.match(pkg)
                        [priority, pkg]
                    end
                end.compact
                matches.sort_by { |priority, pkg| [priority, pkg.name] }
            end

            def run(query_string, format: '$NAME', search_all: false, only_present: false)
                initialize_and_load
                all_selected_packages, * = finalize_setup([], non_imported_packages: :return)
                if search_all
                    packages = ws.manifest.each_package_definition.to_a
                else
                    packages = all_selected_packages.map do |pkg_name|
                        ws.manifest.find_package_definition(pkg_name)
                    end
                end
                if only_present
                    packages = packages.find_all do |pkg|
                        File.directory?(pkg.autobuild.srcdir)
                    end
                end

                if query_string.empty?
                    query = Autoproj::Query.all
                else
                    query = Autoproj::Query.parse_query(query_string.first)
                end
                matches = find_all_matches(query, packages)

                matches.each do |priority, pkg_def|
                    puts format_package(format, priority, pkg_def)
                end
            end

            def format_package(format, priority, package)
                autobuild_package = package.autobuild
                fields = Hash.new
                fields['SRCDIR']   = autobuild_package.srcdir
                fields['BUILDDIR'] = if autobuild_package.respond_to?(:builddir)
                                         autobuild_package.builddir
                                     end
                fields['PREFIX']   = autobuild_package.prefix
                fields['NAME']     = package.name
                fields['PRIORITY'] = priority
                fields['URL']      = (package.vcs.url if !package.vcs.none?)
                fields['PRESENT']  = File.directory?(autobuild_package.srcdir)
                Autoproj.expand(format, fields)
            end
        end
    end
end

