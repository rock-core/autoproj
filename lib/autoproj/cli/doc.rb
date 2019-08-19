require 'autoproj/cli/utility'

module Autoproj
    module CLI
        class Doc < Utility
            def initialize(ws = Workspace.default)
                @utility_name = 'doc'
                super
            end
        end
    end
end
