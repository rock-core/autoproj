# frozen_string_literal: true

module Autoproj
    module AutobuildExtensions
        # Extension for Autobuild::Python
        module Python
            def activate_python
                Autoproj::Python.setup_python_configuration_options(ws: ws)
                Autoproj::Python.assert_python_activated(ws: ws)
            end

            def update_environment
                activate_python
                super
            end
        end
    end
end
