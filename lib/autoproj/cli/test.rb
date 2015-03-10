require 'autoproj/ops/tools'

module Autoproj
    module CLI
        class Test
            include Ops::Tools

            attr_reader :manifest

            def initialize(manifest)
                @manifest = manifest
            end

            def parse_options(args)
                Autoproj.load_config

                modified_config = false
                mode = nil
                options = Hash.new
                option_parser = OptionParser.new do |opt|
                    opt.on '--enable[=PACKAGE,PACKAGE]', Array, 'enable tests for all packages or for specific packages (does not run the tests)' do |packages|
                        if !packages
                            Autoproj.config.utility_enable_all('test')
                        else
                            Autoproj.config.utility_enable_for('test', *packages)
                        end
                        modified_config = true
                    end
                    opt.on '--disable[=PACKAGE,PACKAGE]', Array, 'disable tests for all packages or for specific packages (does not run the tests)' do |packages|
                        if !packages
                            Autoproj.config.utility_disable_all('test')
                        else
                            Autoproj.config.utility_disable_for('test', *packages)
                        end
                        modified_config = true
                    end
                    opt.on '--list', 'list the test availability and enabled/disabled state information' do
                        mode = 'list'
                    end
                    opt.on '--[no-]recursion', '(do not) run or list the tests of the dependencies of the packages given on the command line (the default is false)' do |flag|
                        options[:recursive] = flag
                    end
                end

                user_selection = option_parser.parse(ARGV)
                if !mode && !(modified_config && user_selection.empty?)
                    mode = 'run'
                end

                if modified_config
                    Autoproj.save_config
                end
                return mode, user_selection, options
            end

            def list(user_selection, options = Hash.new)
                resolved_selection = resolve_selection(
                    user_selection,
                    recursive: options[:recursive],
                    ignore_non_imported_packages: true)

                lines = Array.new
                resolved_selection.each do |pkg_name|
                    pkg = manifest.find_package(pkg_name).autobuild
                    lines << [pkg.name, pkg.test_utility.enabled?, pkg.test_utility.available?]
                end
                lines = lines.sort_by { |name, _| name }
                w     = lines.map { |name, _| name.length }.max
                format = "%-#{w}s %-7s %-9s"
                puts format % ["Package Name", "Enabled", "Available"]
                lines.each do |name, enabled, available|
                    puts(format % [name, (!!enabled).to_s, (!!available).to_s])
                end
            end

            def run(user_selection, options = Hash.new)
                packages = resolve_selection(
                    user_selection,
                    recursive: options[:recursive],
                    ignore_non_imported_packages: true)
                # This calls #prepare, which is required to run build_packages
                packages.each do |pkg|
                    Autobuild::Package[pkg].disable_phases('import', 'prepare', 'install')
                end
                Autobuild.apply(packages, "autoproj-test", ['test'])
            end
        end
    end
end

