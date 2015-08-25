require 'autobuild'
module Autoproj
    module CLI
        class InvalidArguments < Autobuild::Exception
        end

        def self.load_plugins
            Gem.find_latest_files('autoproj-*', true).each do |path|
                require path
            end
        end
    end
end

