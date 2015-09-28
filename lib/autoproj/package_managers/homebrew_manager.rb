module Autoproj
    module PackageManagers
        # Package manager interface for Mac OS using homebrew as
        # its package manager
        class HomebrewManager < ShellScriptManager
            def initialize
                super(['brew'], true,
                        "brew install '%s'",
                        "brew install '%s'",
                        false)
            end

            def filter_uptodate_packages(packages, options = Hash.new)
                # TODO there might be duplicates in packages which should be fixed
                # somewhere else
                packages = packages.uniq
                result = `brew info --json=v1 '#{packages.join("' '")}'`
                result = begin
                             JSON.parse(result)
                         rescue JSON::ParserError
                             if result && !result.empty?
                                 Autoproj.warn "Error while parsing result of brew info --json=v1"
                             else
                                 # one of the packages is unknown fallback to install all
                                 # packaes which will complain about it
                             end
                             return packages
                         end
                # fall back if something else went wrong
                if packages.size != result.size
                    Autoproj.warn "brew info returns less or more packages when requested. Falling back to install all packages"
                    return packages
                end

                new_packages = []
                result.each do |pkg|
                    new_packages << pkg["name"] if pkg["installed"].empty?
                end
                new_packages
            end
        end
    end
end

