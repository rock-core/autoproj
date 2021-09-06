require "autoproj/test"

module Autoproj
    describe OSPackageInstaller do
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
            @os_indep_manager = flexmock(os_package_installer.package_managers["os_indep"])
            os_package_installer.osdeps_mode = "os,os_indep"
        end

        describe "#resolve_and_partition_osdep_packages" do
            before do
                ws_define_osdep_entries "pkg0" => Hash["os" => "os:pkg0"]
                ws_define_osdep_entries "pkg1" => Hash["os" => "os:pkg1"]
            end

            it "returns the selected packages for managers that are not strict" do
                os_manager.should_receive(strict?: false)
                assert_equal Hash[os_manager => Set["os:pkg0"]], os_package_installer.
                    resolve_and_partition_osdep_packages(["pkg0"], %w[pkg0 pkg1])
            end
            it "does not invoke non-strict managers if they don't have a selected package" do
                os_manager.should_receive(strict?: false)
                assert_equal Hash.new, os_package_installer.
                    resolve_and_partition_osdep_packages([], %w[pkg0 pkg1])
            end
            it "does call non-strict managers with an empty set if they have call_while_empty" do
                os_manager.should_receive(strict?: false, call_while_empty?: true)
                assert_equal Hash[os_manager => Set[]], os_package_installer.
                    resolve_and_partition_osdep_packages([], %w[pkg0 pkg1])
            end
            it "returns all packages for managers that are strict" do
                os_manager.should_receive(strict?: true)
                assert_equal Hash[os_manager => Set["os:pkg0", "os:pkg1"]], os_package_installer.
                    resolve_and_partition_osdep_packages(["pkg0"], %w[pkg0 pkg1])
            end
            it "does not invoke strict managers if they don't have a selected package" do
                os_manager.should_receive(strict?: true)
                assert_equal Hash[os_manager => Set["os:pkg0", "os:pkg1"]], os_package_installer.
                    resolve_and_partition_osdep_packages(["pkg0"], %w[pkg0 pkg1])
            end
            it "does call strict managers with all the packages if they have call_while_empty" do
                os_manager.should_receive(strict?: true, call_while_empty?: true)
                assert_equal Hash[os_manager => Set["os:pkg0", "os:pkg1"]], os_package_installer.
                    resolve_and_partition_osdep_packages([], %w[pkg0 pkg1])
            end
            it "raises if a strict manager is involved, but the all_osdep_packages argument is not given" do
                os_manager.should_receive(strict?: true)
                assert_raises(InternalError) do
                    os_package_installer.resolve_and_partition_osdep_packages(["pkg0"])
                end
            end
            it "bypasses a strict manager if all_osdep_packages is not given and no explicit package was selected" do
                os_manager.should_receive(strict?: true, call_while_empty?: true)
                assert_equal Hash.new, os_package_installer.
                    resolve_and_partition_osdep_packages([])
            end
            it "adds manager's os dependencies to packages" do
                ws_define_osdep_entries "dependency" => Hash["os" => "dependency_pkg"]
                ws_define_osdep_entries "pkg2" => Hash["os_indep" => "pkg2"]

                os_indep_manager.should_receive(:os_dependencies).and_return(["dependency"])
                assert_equal Hash[os_manager => Set["os:pkg0", "dependency_pkg"], os_indep_manager => Set["pkg2"]],
                    os_package_installer.resolve_and_partition_osdep_packages(%w[pkg0 pkg2])
            end
            it "returns the manager's dependencies" do
                ws_define_osdep_entries "dependency" => Hash["os" => "dependency_pkg"]
                ws_define_osdep_entries "pkg2" => Hash["os_indep" => "pkg2"]

                os_indep_manager.should_receive(:os_dependencies).and_return(["dependency"])
                assert_equal Hash[os_manager => Set["dependency_pkg"], os_indep_manager => Set["pkg2"]],
                    os_package_installer.resolve_and_partition_osdep_packages(["pkg2"])
            end
            it "resolves manager's dependencies recursively" do
                ws_define_osdep_entries "dependency" => Hash["os" => "dependency_pkg"]
                ws_define_osdep_entries "dependency-foo" => Hash["os_indep" => "dependency_foo"]

                os_indep_manager.should_receive(:os_dependencies).and_return(["dependency"])
                os_manager.should_receive(:os_dependencies).and_return(["dependency-foo"])
                assert_equal Hash[os_manager => Set["dependency_pkg", "os:pkg0"], os_indep_manager => Set["dependency_foo"]],
                    os_package_installer.resolve_and_partition_osdep_packages(["pkg0"])
            end
            it "does not add manager's os dependencies if manager not being used" do
                ws_define_osdep_entries "dependency" => Hash["os" => "dependency_pkg"]

                os_indep_manager.should_receive(:os_dependencies).and_return(["dependency"])
                assert_equal Hash[os_manager => Set["os:pkg0"]],
                    os_package_installer.resolve_and_partition_osdep_packages(["pkg0"])
            end
        end
        describe "#install" do
            it "installs the resolved packages" do
                ws_define_osdep_entries({
                    "pkg0" => ["test_os_family" => "test_os_pkg"],
                    "pkg1" => ["os_indep" => "test_os_indep_pkg"]
                })

                os_manager.should_receive(:install).
                    with(["test_os_pkg"], install_only: false, filter_uptodate_packages: true)
                os_indep_manager.should_receive(:install).
                    with(["test_os_indep_pkg"], install_only: false, filter_uptodate_packages: true)

                os_package_installer.install(%w[pkg0 pkg1])
            end

            it "performs the install without problem even if the os package manager is not involved" do
                ws_define_osdep_entries({
                    "pkg" => ["os_indep" => "test_os_indep_pkg"]
                })
                os_manager.should_receive(:install).never
                os_indep_manager.should_receive(:install).
                    with(["test_os_indep_pkg"], install_only: false, filter_uptodate_packages: true)

                os_package_installer.install(["pkg"])
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
                ws_define_osdep_entries({ "pkg" => ["os_indep" => "test_os_indep_pkg"] })
                os_indep_manager.should_receive(:install).
                    with(["test_os_indep_pkg"], install_only: false, filter_uptodate_packages: true)

                os_package_installer.install(["pkg"], run_package_managers_without_packages: false)
            end
        end
    end
end
