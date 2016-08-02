require 'autoproj/test'

module Autoproj
    describe OSPackageInstaller do
        def create_osdep(data, file = nil)
            if data
                osdeps = OSPackageResolver.new(Hash['pkg' => data], file)
            else
                osdeps = OSPackageResolver.new(Hash.new, file)
            end

            # Mock the package handlers
            osdeps.os_package_manager = 'os-manager'
            osdeps.package_managers.clear
            osdeps.package_managers << 'os-manager' << 'gem'
            flexmock(osdeps)
        end

        attr_reader :resolver
        attr_reader :installer
        attr_reader :os_manager
        attr_reader :gem_manager

        before do
            ws = flexmock
            @resolver = create_osdep(Hash.new)
            @os_manager  = flexmock(PackageManagers::Manager.new(ws))
            @gem_manager = flexmock(PackageManagers::Manager.new(ws))
            @installer = flexmock(
                OSPackageInstaller.new(ws, resolver),
                os_package_manager: os_manager,
                package_managers: Hash['os-manager' => os_manager, 'gem' => gem_manager])

        end

        it "installs the resolved packages" do
            resolver.should_receive(:resolve_os_packages).
                once.with(['pkg0', 'pkg1', 'pkg2'].to_set).
                and_return([[resolver.os_package_manager, ['os0.1', 'os0.2', 'os1']],
                            ['gem', [['gem2', '>= 0.9']]]])

            # Do not add filter_uptodate_packages to the gem handler to check that
            # #install deals with that just fine
            installer.os_package_manager.should_receive(:install).
                with(['os0.1', 'os0.2', 'os1'], install_only: false, filter_uptodate_packages: true)
            installer.package_managers['gem'].should_receive(:install).
                with([['gem2', '>= 0.9']], install_only: false, filter_uptodate_packages: true)

            installer.osdeps_mode = 'all'
            installer.install(['pkg0', 'pkg1', 'pkg2'])
        end

        it "runs the package managers without packages if run_package_managers_without_packages is true and the handler has call_while_empty set" do
            resolver.should_receive(:resolve_os_packages).
                once.and_return([])

            installer.package_managers['gem'].should_receive(:install).
                with([], filter_uptodate_packages: true, install_only: false).once
            gem_manager.should_receive(:call_while_empty?).and_return(true)
            installer.osdeps_mode = 'all'
            installer.install(['pkg0', 'pkg1', 'pkg2'], run_package_managers_without_packages: true)
        end

        it "does not run package managers without packages if run_package_managers_without_packages is true but the handler does not have call_while_empty set" do
            resolver.should_receive(:resolve_os_packages).once.and_return([])

            installer.package_managers['gem'].should_receive(:install).never
            gem_manager.should_receive(:call_while_empty?).and_return(false)
            installer.osdeps_mode = 'all'
            installer.install(['pkg0', 'pkg1', 'pkg2'], run_package_managers_without_packages: true)
        end

        it "does run package managers with packages regardless of call_while_empty" do
            resolver.should_receive(:resolve_os_packages).once.and_return([['gem', ['gem_name']]])

            installer.package_managers['gem'].should_receive(:install).once
            gem_manager.should_receive(:call_while_empty?).and_return(false)
            installer.osdeps_mode = 'all'
            installer.install(['pkg0', 'pkg1', 'pkg2'], run_package_managers_without_packages: false)
        end
    end
end

