require 'autoproj/test'

module Autoproj
    describe OSPackageInstaller do
        describe "#install" do
            attr_reader :os_package_installer
            attr_reader :os_manager
            attr_reader :os_indep_manager

            before do
                # Use the helpers, but avoid creating a workspace
                ws = flexmock
                ws_create_os_package_resolver
                @os_package_installer = OSPackageInstaller.new(
                    ws,
                    ws_os_package_resolver,
                    package_managers: ws_package_managers)

                @os_manager       = flexmock(os_package_installer.os_package_manager)
                @os_indep_manager = flexmock(os_package_installer.package_managers['os_indep'])
                os_package_installer.osdeps_mode = 'os,os_indep'
            end

            it "installs the resolved packages" do
                ws_add_osdep_entries(
                    'pkg0' => ['test_os_family' => 'test_os_pkg'],
                    'pkg1' => ['os_indep' => 'test_os_indep_pkg'])

                os_manager.should_receive(:install).
                    with(['test_os_pkg'], install_only: false, filter_uptodate_packages: true)
                os_indep_manager.should_receive(:install).
                    with(['test_os_indep_pkg'], install_only: false, filter_uptodate_packages: true)

                os_package_installer.install(['pkg0', 'pkg1'])
            end

            it "performs the install without problem even if the os package manager is not involved" do
                ws_add_osdep_entries(
                    'pkg' => ['os_indep' => 'test_os_indep_pkg'])
                os_manager.should_receive(:install).never
                os_indep_manager.should_receive(:install).
                    with(['test_os_indep_pkg'], install_only: false, filter_uptodate_packages: true)

                os_package_installer.install(['pkg'])
            end

            it "runs the package managers without packages if run_package_managers_without_packages is true and the handler has call_while_empty set" do

                os_indep_manager.should_receive(:install).
                    with([], filter_uptodate_packages: true, install_only: false).once
                os_indep_manager.should_receive(:call_while_empty?).and_return(true)
                os_package_installer.install([], run_package_managers_without_packages: true)
            end

            it "does not run package managers without packages if run_package_managers_without_packages is true but the handler does not have call_while_empty set" do
                os_indep_manager.should_receive(:install).never
                os_indep_manager.should_receive(:call_while_empty?).and_return(false)
                os_package_installer.install([], run_package_managers_without_packages: true)
            end

            it "does run package managers with packages regardless of call_while_empty" do
                ws_add_osdep_entries('pkg' => ['os_indep' => 'test_os_indep_pkg'])
                os_indep_manager.should_receive(:install).
                    with(['test_os_indep_pkg'], install_only: false, filter_uptodate_packages: true)

                os_package_installer.install(['pkg'], run_package_managers_without_packages: false)
            end
        end
    end
end

