module Autoproj
    module PackageManagers
        # Base class for all package managers that simply require the call of a
        # shell script to install packages (e.g. yum, apt, ...)
        class ShellScriptManager < Manager
            def self.execute(script, with_locking, with_root)
                if with_locking
                    File.open('/tmp/autoproj_osdeps_lock', 'w') do |lock_io|
                        begin
                            while !lock_io.flock(File::LOCK_EX | File::LOCK_NB)
                                Autoproj.message "  waiting for other autoproj instances to finish their osdeps installation"
                                sleep 5
                            end
                            return execute(script, false,with_root)
                        ensure
                            lock_io.flock(File::LOCK_UN)
                        end
                    end
                end
                
                sudo = Autobuild.tool_in_path('sudo')
                Tempfile.open('osdeps_sh') do |io|
                    io.puts "#! /bin/bash"
                    io.puts GAIN_ROOT_ACCESS % [sudo] if with_root
                    io.write script
                    io.flush
                    Autobuild::Subprocess.run 'autoproj', 'osdeps', '/bin/bash', io.path
                end
            end

            GAIN_ROOT_ACCESS = <<-EOSCRIPT
# Gain root access using sudo
if test `id -u` != "0"; then
    exec %s /bin/bash $0 "$@"

fi
            EOSCRIPT

            # Overrides the {#needs_locking?} flag
            attr_writer :needs_locking
            # Whether two autoproj instances can run this package manager at the
            # same time
            #
            # This declares if this package manager cannot be used concurrently.
            # If it is the case, autoproj will ensure that there is no two
            # autoproj instances running this package manager at the same time
            # 
            # @return [Boolean]
            # @see needs_locking=
            def needs_locking?; !!@needs_locking end

            # Overrides the {#needs_root?} flag
            attr_writer :needs_root
            # Whether this package manager needs root access.
            #
            # This declares if the command line(s) for this package manager
            # should be started as root. Root access is provided using sudo
            # 
            # @return [Boolean]
            # @see needs_root=
            def needs_root?; !!@needs_root end

            # Command line used by autoproj to install packages
            #
            # Since it is to be used for automated install by autoproj, it
            # should not require any interaction with the user. When generating
            # the command line, the %s slot is replaced by the quoted package
            # name(s).
            #
            # @return [String] a command line pattern that allows to install
            #   packages without user interaction. It is used when a package
            #   should be installed by autoproj automatically
            attr_reader :auto_install_cmd
            # Command line displayed to the user to install packages
            #
            # When generating the command line, the %s slot is replaced by the
            # quoted package name(s).
            #
            # @return [String] a command line pattern that allows to install
            #   packages with user interaction. It is displayed to the
            #   user when it chose to not let autoproj install packages for this
            #   package manager automatically
            attr_reader :user_install_cmd

            # @param [Array<String>] names the package managers names, see
            #   {#names}
            # @param [Boolean] needs_locking whether this package manager can be
            #   started by two separate autoproj instances at the same time. See
            #   {#needs_locking?}
            # @param [String] user_install_cmd the user-visible command line. See
            #   {#user_install_cmd}
            # @param [String] auto_install_cmd the command line used by autoproj
            #   itself, see {#auto_install_cmd}.
            # @param [Boolean] needs_root if the command lines should be started
            #   as root or not. See {#needs_root?}
            def initialize(ws, needs_locking, user_install_cmd, auto_install_cmd,needs_root=true)
                super(ws)
                @needs_locking, @user_install_cmd, @auto_install_cmd,@needs_root =
                    needs_locking, user_install_cmd, auto_install_cmd, needs_root
            end

            # Generate the shell script that would allow the user to install
            # the given packages
            #
            # @param [Array<String>] os_packages the name of the packages to be
            #   installed
            # @option options [String] :user_install_cmd (#user_install_cmd) the
            #   command-line pattern that should be used to generate the script.
            #   If given, it overrides the default value stored in
            #   {#user_install_cmd]
            def generate_user_os_script(os_packages, user_install_cmd: self.user_install_cmd)
                if user_install_cmd
                    (user_install_cmd % [os_packages.join("' '")])
                else generate_auto_os_script(os_packages)
                end
            end

            # Generate the shell script that should be executed by autoproj to
            # install the given packages
            #
            # @param [Array<String>] os_packages the name of the packages to be
            #   installed
            # @option options [String] :auto_install_cmd (#auto_install_cmd) the
            #   command-line pattern that should be used to generate the script.
            #   If given, it overrides the default value stored in
            #   {#auto_install_cmd]
            def generate_auto_os_script(os_packages, auto_install_cmd: self.auto_install_cmd)
                (auto_install_cmd % [os_packages.join("' '")])
            end

            # Handles interaction with the user
            #
            # This method will verify whether the user required autoproj to
            # install packages from this package manager automatically. It
            # displays a relevant message if it is not the case.
            #
            # @return [Boolean] true if the packages should be installed
            #   automatically, false otherwise
            def osdeps_interaction(os_packages, shell_script)
                if OSPackageInstaller.force_osdeps
                    return true
                elsif enabled?
                    return true
                elsif silent?
                    return false
                end

                # We're asked to not install the OS packages but to display them
                # anyway, do so now
                puts <<-EOMSG

                #{Autoproj.color("The build process and/or the packages require some other software to be installed", :bold)}
                #{Autoproj.color("and you required autoproj to not install them itself", :bold)}
                #{Autoproj.color("\nIf these packages are already installed, simply ignore this message\n", :red) if !respond_to?(:filter_uptodate_packages)}
    The following packages are available as OS dependencies, i.e. as prebuilt
    packages provided by your distribution / operating system. You will have to
    install them manually if they are not already installed

                #{os_packages.sort.join("\n      ")}

    the following command line(s) can be run as root to install them:

                #{shell_script.split("\n").join("\n|   ")}

            EOMSG
                print "    #{Autoproj.color("Press ENTER to continue ", :bold)}"
                STDOUT.flush
                STDIN.readline
                puts
                false
            end

            # Install packages using this package manager
            #
            # @param [Array<String>] packages the name of the packages that
            #   should be installed
            # @option options [String] :user_install_cmd (#user_install_cmd) the
            #   command line that should be displayed to the user to install said
            #   packages. See the option in {#generate_user_os_script}
            # @option options [String] :auto_install_cmd (#auto_install_cmd) the
            #   command line that should be used by autoproj to install said
            #   packages. See the option in {#generate_auto_os_script}
            # @return [Boolean] true if packages got installed, false otherwise
            def install(packages, filter_uptodate_packages: false, install_only: false,
                        auto_install_cmd: self.auto_install_cmd, user_install_cmd: self.user_install_cmd)
                return if packages.empty?

                handled_os = ws.supported_operating_system?
                if handled_os
                    shell_script = generate_auto_os_script(packages, auto_install_cmd: auto_install_cmd)
                    user_shell_script = generate_user_os_script(packages, user_install_cmd: user_install_cmd)
                end
                if osdeps_interaction(packages, user_shell_script)
                    Autoproj.message "  installing OS packages: #{packages.sort.join(", ")}"

                    if Autoproj.verbose
                        Autoproj.message "Generating installation script for non-ruby OS dependencies"
                        Autoproj.message shell_script
                    end
                    ShellScriptManager.execute(shell_script, needs_locking?,needs_root?)
                    return true
                end
                false
            end
        end
    end
end

