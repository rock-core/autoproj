require 'autoproj/cli/base'

module Autoproj
    module CLI
        # Base class for CLI tools that do not change the state of the installed
        # system
        class InspectionTool
            include Ops::Tools

            attr_reader :ws

            def initialize_and_load
                Autoproj.silent do
                    ws = Workspace.from_environment
                    ws.setup
                    ws.load_package_sets
                    ws.setup_all_package_directories
                    return ws
                end
            end

            def load_all_available_package_manifests
                # Load the manifest for packages that are already present on the
                # file system
                ws.manifest.packages.each_value do |pkg|
                    if File.directory?(pkg.autobuild.srcdir)
                        begin
                            ws.manifest.load_package_manifest(pkg.autobuild.name)
                        rescue Interrupt
                            raise
                        rescue Exception => e
                            Autoproj.warn "cannot load package manifest for #{pkg.autobuild.name}: #{e.message}"
                        end
                    end
                end
            end

            def initialize(ws = nil)
                if !ws
                    ws = initialize_and_load
                end
                @ws = ws
            end
        end
    end
end
