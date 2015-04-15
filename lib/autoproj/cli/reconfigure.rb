module Autoproj
    module CLI
        class Reconfigure
            attr_reader :ws

            def initialize(ws = Workspace.from_environment)
                @ws = ws
            end

            def parse_options(argv)
                options = Hash.new
                parser = OptionParser.new do |opt|
                    opt.banner = ["autoproj reconfigure",
                                  "asks the configuration questions from the build configuration, and allows to set parameters that influence autoproj through command-line options"]
                    opt.on '--[no-]separate-prefixes' do |flag|
                        options['separate_prefixes'] = flag
                    end
                end
                parser.parse(argv)
                options
            end

            def run(options)
                ws.setup
                ws.config.reconfigure!
                options.each do |k, v|
                    ws.config.set k, v, true
                end
                ws.load_package_sets
                ws.setup_all_package_directories
                ws.finalize_package_setup
                ws.config.save
            end
        end
    end
end

