require "autoproj/cli/utility"

module Autoproj
    module CLI
        class Doc < Utility
            def initialize(ws = Workspace.default, name: "doc")
                super
            end
        end
    end
end
