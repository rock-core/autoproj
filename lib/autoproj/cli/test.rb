require "autoproj/cli/utility"

module Autoproj
    module CLI
        class Test < Utility
            def initialize(ws = Workspace.default,
                name: "test",
                report_path: ws.utility_report_path("test"))
                super
            end

            def package_metadata(package)
                u = package.test_utility
                super.merge(
                    "coverage_available" => !!u.coverage_available?,
                    "coverage_enabled" => !!u.coverage_enabled?,
                    "coverage_source_dir" => u.coverage_source_dir,
                    "coverage_target_dir" => u.coverage_target_dir
                )
            end
        end
    end
end
