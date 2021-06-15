require 'autoproj/python'

module Autoproj
    module PackageManagers
        # Using pip to install python packages
        class PipManager < Manager
            attr_reader :installed_pips

            def initialize_environment
                ws.env.set 'PYTHONUSERBASE', pip_home
                ws.env.add_path 'PATH', File.join(pip_home, 'bin')
            end

            # Return the directory where python packages are installed to.
            # The actual path is pip_home/lib/pythonx.y/site-packages.
            def pip_home
                ws.env['AUTOPROJ_PYTHONUSERBASE'] || File.join(ws.prefix_dir, "pip")
            end

            def initialize(ws)
                super(ws)
                @installed_pips = Set.new
            end

            def os_dependencies
                super + ['pip']
            end

            def guess_pip_program
                if ws.config.has_value_for?('USE_PYTHON')
                    unless ws.config.get('USE_PYTHON')
                        raise ConfigError, "Your current package selection" \
                          " requires the use of pip is required, but" \
                          " the use of python has been denied, see" \
                          " setting of USE_PYTHON in your workspace configuration." \
                          " Either remove all packages depending on pip packages " \
                          " from the workspace layout (manifest) or " \
                          " call 'autoproj reconfigure' to change the setting."
                    end
                else
                    Autoproj::Python.setup_python_configuration_options(ws: ws)
                    @use_python_venv = ws.config.get("USE_PYTHON_VENV", nil)
                end

                return Autobuild.programs['pip'] if Autobuild.programs['pip']

                Autobuild.programs['pip'] = "pip"
            end

            # rubocop:disable Lint/UnusedMethodArgument
            def install(pips, filter_uptodate_packages: false, install_only: false)
                guess_pip_program
                pips = [pips] if pips.is_a?(String)

                base_cmdline = [Autobuild.tool('pip'), 'install', '--user']

                cmdlines = [base_cmdline + pips]

                if pips_interaction(cmdlines)
                    Autoproj.message "  installing/updating Python dependencies:" \
                        " #{pips.sort.join(', ')}"

                    cmdlines.each do |c|
                        Autobuild::Subprocess.run 'autoproj', 'osdeps', *c,
                                                  env: ws.env.resolved_env
                    end

                    pips.each do |p|
                        @installed_pips << p
                    end
                end
            end
            # rubocop:enable Lint/UnusedMethodArgument

            def pips_interaction(cmdlines)
                if OSPackageInstaller.force_osdeps
                    return true
                elsif enabled?
                    return true
                elsif silent?
                    return false
                end

                # We're not supposed to install rubygem packages but silent is not
                # set, so display information about them anyway
                puts <<-EOMSG
      #{Autoproj.color('The build process and/or the packages require some Python packages to be installed', :bold)}
      #{Autoproj.color('and you required autoproj to not do it itself', :bold)}
        The following command line can be used to install them manually
#{'        '}
          #{cmdlines.map { |c| c.join(' ') }.join("\n      ")}
#{'        '}
        Autoproj expects these Python packages to be installed in #{pip_home} This can
        be overridden by setting the AUTOPROJ_PYTHONUSERBASE environment variable manually

                EOMSG
                print "    #{Autoproj.color('Press ENTER to continue ', :bold)}"

                $stdout.flush
                $stdin.readline
                puts
                false
            end
        end
    end
end
