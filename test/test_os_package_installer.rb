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

        def test_install
            ws = flexmock
            resolver = create_osdep(Hash.new)
            os_manager  = flexmock(PackageManagers::Manager.new(ws))
            gem_manager = flexmock(PackageManagers::Manager.new(ws))
            installer = flexmock(
                OSPackageInstaller.new(ws, resolver),
                os_package_manager: os_manager,
                package_managers: Hash['os-manager' => os_manager, 'gem' => gem_manager])

            resolver.should_receive(:resolve_os_packages).
                once.with(['pkg0', 'pkg1', 'pkg2'].to_set).
                and_return([[resolver.os_package_manager, ['os0.1', 'os0.2', 'os1']],
                            ['gem', [['gem2', '>= 0.9']]]])
            installer.os_package_manager.should_receive(:filter_uptodate_packages).
                with(['os0.1', 'os0.2', 'os1'], install_only: false).and_return(['os0.1', 'os1']).once
            # Do not add filter_uptodate_packages to the gem handler to check that
            # #install deals with that just fine
            installer.os_package_manager.should_receive(:install).
                with(['os0.1', 'os1'])
            installer.package_managers['gem'].should_receive(:install).
                with([['gem2', '>= 0.9']])

            installer.osdeps_mode = 'all'
            installer.install(['pkg0', 'pkg1', 'pkg2'])
        end
    end
end

