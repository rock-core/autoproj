require 'autoproj/cli/utility'

module Autoproj
    module CLI
        class Test < Utility
            def initialize(ws = Workspace.default)
                @utility_name = 'test'
                super
            end
        end
    end
end
