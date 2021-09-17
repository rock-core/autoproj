require "autoproj/repository_managers/manager"
require "autoproj/repository_managers/unknown_os_manager"
require "autoproj/repository_managers/apt"

module Autoproj
    class OSRepositoryInstaller
        # The workspace object
        attr_reader :ws

        # Returns the set of repository managers
        attr_reader :repository_managers

        OS_REPOSITORY_MANAGERS = {
            "debian" => RepositoryManagers::APT
        }.freeze

        def initialize(ws)
            @ws = ws
            @repository_managers = {}
            OS_REPOSITORY_MANAGERS.each do |name, klass|
                @repository_managers[name] = klass.new(ws)
            end
        end

        def os_repository_resolver
            ws.os_repository_resolver
        end

        # Returns the repository manager object for the current OS
        def os_repository_manager
            return @os_repository_manager if @os_repository_manager

            os_names, = os_repository_resolver.operating_system
            os_name = os_names.find { |name| OS_REPOSITORY_MANAGERS[name] }

            @os_repository_manager =
                repository_managers[os_name] ||
                RepositoryManagers::UnknownOSManager.new(ws)
        end

        def each_manager(&block)
            repository_managers.each_value(&block)
        end

        def install_os_repositories
            return if os_repository_resolver.resolved_entries.empty?

            deps = os_repository_manager.os_dependencies
            ws.install_os_packages(deps, all: nil) unless deps.empty?
            os_repository_manager.install(os_repository_resolver.resolved_entries)
        end
    end
end
