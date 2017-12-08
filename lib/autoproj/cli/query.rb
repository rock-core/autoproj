require 'autoproj'
require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Query < InspectionTool
            def os_package_resolver
                ws.os_package_resolver
            end

            def find_all_matches(query, packages)
                matches = packages.map do |pkg|
                    if priority = query.match(pkg)
                        [priority, pkg]
                    end
                end.compact
                matches.sort_by { |priority, pkg| [priority, pkg.name] }
            end

            def run(query_string, format: '$NAME', search_all: false, only_present: false, osdeps: false)
                initialize_and_load
                all_selected_packages, all_selected_osdeps_packages, * =
                    finalize_setup([], non_imported_packages: :return)

                if osdeps
                    query_os_packages(query_string, all_selected_osdeps_packages, format: format, search_all: search_all)
                else
                    query_source_packages(query_string, all_selected_packages, format: format, search_all: search_all, only_present: only_present)
                end
            end

            def query_os_packages(query_string, selected_packages, format: '$NAME', search_all: false)
                if query_string.empty?
                    query = OSPackageQuery.all
                else
                    query = OSPackageQuery.parse_query(query_string.first, os_package_resolver)
                end

                if search_all
                    packages = os_package_resolver.all_package_names
                else
                    packages = selected_packages
                end

                matches = find_all_matches(query, packages.to_a)

                needs_real_package = (/\$REAL_PACKAGE\b/ === format)
                needs_handler = (/\$HANDLER\b/ === format)

                matches.each do |priority, pkg_name|
                    if needs_real_package || needs_handler
                        resolved = os_package_resolver.resolve_os_packages([pkg_name])
                        resolved.each do |handler, real_packages|
                            if needs_real_package
                                real_packages.each do |real_package_name|
                                    puts format_osdep_package(format, priority, pkg_name, handler, real_package_name)
                                end
                            else
                                puts format_osdep_package(format, priority, pkg_name, handler, nil)
                            end
                        end
                    else
                        puts format_osdep_package(format, priority, pkg_name, nil, nil)
                    end
                end
            end

            def format_osdep_package(format, priority, name, handler, real_package_name)
                fields = Hash.new
                fields['NAME']     = name
                fields['PRIORITY'] = priority
                fields['HANDLER']  = handler
                fields['REAL_PACKAGE']  = real_package_name
                Autoproj.expand(format, fields)
            end

            def query_source_packages(query_string, selected_packages, format: '$NAME', search_all: false, only_present: false)
                if query_string.empty?
                    query = SourcePackageQuery.all
                else
                    query = SourcePackageQuery.parse_query(query_string.first)
                end

                if search_all
                    packages = ws.manifest.each_package_definition.to_a
                else
                    packages = selected_packages.map do |pkg_name|
                        ws.manifest.find_package_definition(pkg_name)
                    end
                end

                if only_present
                    packages = packages.find_all do |pkg|
                        File.directory?(pkg.autobuild.srcdir)
                    end
                end

                matches = find_all_matches(query, packages)

                matches.each do |priority, pkg_def|
                    puts format_source_package(format, priority, pkg_def)
                end
            end

            def format_source_package(format, priority, package)
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

