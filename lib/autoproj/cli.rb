module Autoproj
    module CLI
        class InvalidArguments < Exception
        end

        def self.load_plugins
            finder_name =
                if Gem.respond_to?(:find_latest_files)
                    :find_latest_files
                else
                    :find_files
                end

            Gem.send(finder_name, 'autoproj-*', true).each do |path|
                require path
            end
        end
    end
end

