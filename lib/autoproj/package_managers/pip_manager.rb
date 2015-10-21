module Autoproj
    module PackageManagers
        # Using pip to install python packages
        class PipManager < Manager
            attr_reader :installed_pips

            def initialize_environment
                ws.env.set 'PYTHONUSERBASE', pip_home
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

            def guess_pip_program
                if Autobuild.programs['pip']
                    return Autobuild.programs['pip']
                end

                Autobuild.programs['pip'] = "pip"
            end

            def install(pips, filter_uptodate_packages: false, install_only: false)
                guess_pip_program
                if pips.is_a?(String)
                    pips = [pips]
                end

                base_cmdline = [Autobuild.tool('pip'), 'install','--user']

                cmdlines = [base_cmdline + pips]

                if pips_interaction(pips, cmdlines)
                    Autoproj.message "  installing/updating Python dependencies: "+
                        "#{pips.sort.join(", ")}"

                    cmdlines.each do |c|
                        Autobuild::Subprocess.run 'autoproj', 'osdeps', *c
                    end

                    pips.each do |p|
                        @installed_pips << p
                    end
                end
            end
            
            def pips_interaction(pips, cmdlines)
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
      #{Autoproj.color("The build process and/or the packages require some Python packages to be installed", :bold)}
      #{Autoproj.color("and you required autoproj to not do it itself", :bold)}
        The following command line can be used to install them manually
        
          #{cmdlines.map { |c| c.join(" ") }.join("\n      ")}
        
        Autoproj expects these Python packages to be installed in #{pip_home} This can
        be overridden by setting the AUTOPROJ_PYTHONUSERBASE environment variable manually

                EOMSG
                print "    #{Autoproj.color("Press ENTER to continue ", :bold)}"

                STDOUT.flush
                STDIN.readline
                puts
                false
            end
        end
    end
end

