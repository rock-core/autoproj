require 'thor'

module Autoproj
    module CLI
        class Main < Thor
            class_option :verbose, type: :boolean,
                desc: 'turns verbose output',
                default: false
            class_option :debug, type: :boolean,
                desc: 'turns debugging output',
                default: false
            class_option :silent, type: :boolean,
                desc: 'tell autoproj to not display anything',
                default: false
            class_option :progress, type: :boolean,
                desc: 'enables or disables progress display (enabled by default)',
                default: true

            desc 'bootstrap VCS_TYPE VCS_URL VCS_OPTIONS', 'bootstraps a new autoproj installation. This is usually not called directly, but called from the autoproj_bootstrap standalone script'
            option :reuse,
                banner: 'DIR',
                desc: 'reuse packages already built within the DIR autoproj workspace in this installation, if DIR is not given, reuses the installation whose env.sh is currently sourced'
            def bootstrap(*args)
                require 'autoproj/cli/bootstrap'
                cli = Autoproj::CLI::Bootstrap.new
                Autoproj::CmdLine.report do
                    args, options = cli.validate_options(args, self.options.dup)
                    cli.run(args, options)
                end
            end
        end
    end
end
