require "autoproj/test"

module Autoproj
    module PackageManagers
        describe AptDpkgManager do
            def test_status_file_parsing
                file = File.expand_path("apt-dpkg-status", __dir__)
                ws = flexmock
                mng = Autoproj::PackageManagers::AptDpkgManager.new(ws, file)
                assert mng.installed?("installed-package")
                assert !mng.installed?("noninstalled-package")
            end

            it "reports provided packages as installed" do
                file = File.expand_path("apt-dpkg-status", __dir__)
                ws = flexmock
                mng = Autoproj::PackageManagers::AptDpkgManager.new(ws, file)
                assert mng.installed?("xorg-driver-input")
            end

            def test_status_file_parsing_is_robust_to_invalid_utf8
                Tempfile.open "osdeps_aptdpkg" do |io|
                    io.puts "Package: \x80\nStatus: installed ok install\n\nPackage: installed\nStatus: installed ok install"
                    io.flush
                    mng = Autoproj::PackageManagers::AptDpkgManager.new(io.path)
                    mng.installed?("installed")
                end
            end

            def test_status_file_parsing_last_entry_installed
                file = File.expand_path("apt-dpkg-status.installed-last", __dir__)
                mng = Autoproj::PackageManagers::AptDpkgManager.new(flexmock, file)
                assert mng.installed?("installed-package")
            end

            def test_status_file_parsing_last_entry_not_installed
                file = File.expand_path("apt-dpkg-status.noninstalled-last", __dir__)
                mng = Autoproj::PackageManagers::AptDpkgManager.new(flexmock, file)
                assert !mng.installed?("noninstalled-package")
            end

            def test_status_file_parsing_not_there_means_not_installed
                file = File.expand_path("apt-dpkg-status.noninstalled-last", __dir__)
                mng = Autoproj::PackageManagers::AptDpkgManager.new(flexmock, file)
                assert !mng.installed?("non-existent-package")
            end

            describe "parse_dpkg_status" do
                it "reports virtual packages as installed if 'virtual' is true" do
                    file = File.expand_path("apt-dpkg-status", __dir__)
                    installed, = AptDpkgManager.parse_dpkg_status(
                        file, virtual: true
                    )
                    assert_equal %w[installed-package xorg-driver-input].to_set, installed
                end

                it "does not report virtual packages if 'virtual' is false" do
                    file = File.expand_path("apt-dpkg-status", __dir__)
                    installed, = AptDpkgManager.parse_dpkg_status(
                        file, virtual: false
                    )
                    assert_equal %w[installed-package].to_set, installed
                end
            end

            describe "#install" do
                before do
                    file = File.expand_path("apt-dpkg-status",
                                            File.dirname(__FILE__))
                    @mng = AptDpkgManager.new(ws_create, file)
                    flexmock(ShellScriptManager).should_receive(:execute).by_default
                    flexmock(@mng)
                end

                it "does not call parse_packages_versions if the manager is not "\
                   "configured to update the packages" do
                    @mng.keep_uptodate = false
                    flexmock(AptDpkgManager).should_receive(:parse_packages_versions).never
                    @mng.install(["non-existent-package"],
                                 filter_uptodate_packages: true)
                end

                it "does not call parse_packages_versions in install_only mode" do
                    flexmock(AptDpkgManager).should_receive(:parse_packages_versions).never
                    @mng.install(["non-existent-package"],
                                 filter_uptodate_packages: true, install_only: true)
                end

                it "install packages that are out of date if keep_uptodate? is set" do
                    flexmock(AptDpkgManager).should_receive(:parse_packages_versions)
                                            .never
                    ShellScriptManager.should_receive(:execute)
                                      .with(->(cmd) { cmd.include?("installed-package") },
                                            any, any, any).once
                    AptDpkgManager
                        .should_receive(:parse_packages_versions)
                        .with(["installed-package"])
                        .and_return("installed-package" => DebianVersion.new("2:1.0"))
                    @mng.install(["installed-package"],
                                 filter_uptodate_packages: true, install_only: false)
                end

                it "install_only overrides keep_uptodate?" do
                    flexmock(AptDpkgManager).should_receive(:parse_packages_versions)
                                            .never
                    ShellScriptManager.should_receive(:execute).never
                    AptDpkgManager
                        .should_receive(:parse_packages_versions)
                        .with(["installed-package"])
                        .and_return("installed-package" => DebianVersion.new("2:1.0"))
                    @mng.install(["installed-package"],
                                 filter_uptodate_packages: true, install_only: true)
                end

                it "installs non-installed packages" do
                    flexmock(AptDpkgManager).should_receive(:parse_packages_versions)
                                            .never
                    ShellScriptManager
                        .should_receive(:execute)
                        .with(->(cmd) { cmd.include?("noninstalled-package") },
                              any, any, any).once
                    @mng.install(["noninstalled-package"],
                                 filter_uptodate_packages: true, install_only: true)
                end
            end

            LESS = :<
            EQUAL = :==
            GREATER = :>

            def assert_version(a, operator, b)
                a = Autoproj::PackageManagers::DebianVersion.new(a)
                b = Autoproj::PackageManagers::DebianVersion.new(b)
                assert_operator(a, operator, b)
            end

            # Tests extracted from https://github.com/Debian/apt/blob/master/test/libapt/compareversion_test.cc
            def test_apt_package_version_comparison
                assert_version "7.6p2-4", GREATER, "7.6-0"
                assert_version "1.0.3-3", GREATER, "1.0-1"
                assert_version "1.3", GREATER, "1.2.2-2"
                assert_version "1.3", GREATER, "1.2.2"
                assert_version "0-pre", EQUAL, "0-pre"
                assert_version "0-pre", LESS, "0-pree"
                assert_version "1.1.6r2-2", GREATER, "1.1.6r-1"
                assert_version "2.6b2-1", GREATER, "2.6b-2"
                assert_version "98.1p5-1", LESS, "98.1-pre2-b6-2"
                assert_version "0.4a6-2", GREATER, "0.4-1"
                assert_version "1:3.0.5-2", LESS, "1:3.0.5.1"
                assert_version "1:0.4", GREATER, "10.3"
                assert_version "1:1.25-4", LESS, "1:1.25-8"
                assert_version "0:1.18.36", EQUAL, "1.18.36"
                assert_version "1.18.36", GREATER, "1.18.35"
                assert_version "0:1.18.36", GREATER, "1.18.35"
                assert_version "9:1.18.36:5.4-20", LESS, "10:0.5.1-22"
                assert_version "9:1.18.36:5.4-20", LESS, "9:1.18.36:5.5-1"
                assert_version "9:1.18.36:5.4-20", LESS, " 9:1.18.37:4.3-22"
                assert_version "1.18.36-0.17.35-18", GREATER, "1.18.36-19"
                assert_version "1:1.2.13-3", LESS, "1:1.2.13-3.1"
                assert_version "2.0.7pre1-4", LESS, "2.0.7r-1"
                assert_version "0:0-0-0", GREATER, "0-0"
                assert_version "0", EQUAL, "0"
                assert_version "0", EQUAL, "00"
                assert_version "3.0~rc1-1", LESS, "3.0-1"
                assert_version "1.0", EQUAL, "1.0-0"
                assert_version "0.2", LESS, "1.0-0"
                assert_version "1.0", LESS, "1.0-0+b1"
                assert_version "1.0", GREATER, "1.0-0~"
                assert_version "1.2.3", EQUAL, "1.2.3" # identical
                assert_version "4.4.3-2", EQUAL, "4.4.3-2" # identical
                assert_version "1:2ab:5", EQUAL, "1:2ab:5" # this is correct...
                assert_version "7:1-a:b-5", EQUAL, "7:1-a:b-5" # and this
                assert_version "57:1.2.3abYZ+~-4-5", EQUAL, "57:1.2.3abYZ+~-4-5" # and those too
                assert_version "1.2.3", EQUAL, "0:1.2.3" # zero epoch
                assert_version "1.2.3", EQUAL, "1.2.3-0" # zero revision
                assert_version "009", EQUAL, "9" # zeroes
                assert_version "009ab5", EQUAL, "9ab5" # there as well
                assert_version "1.2.3", LESS, "1.2.3-1" # added non-zero revision
                assert_version "1.2.3", LESS, "1.2.4" # just bigger
                assert_version "1.2.4", GREATER, "1.2.3" # order doesn't matter
                assert_version "1.2.24", GREATER, "1.2.3" # bigger, eh?
                assert_version "0.10.0", GREATER, "0.8.7" # bigger, eh?
                assert_version "3.2", GREATER, "2.3" # major number rocks
                assert_version "1.3.2a", GREATER, "1.3.2" # letters rock
                assert_version "0.5.0~git", LESS, "0.5.0~git2" # numbers rock
                assert_version "2a", LESS, "21" # but not in all places
                assert_version "1.3.2a", LESS, "1.3.2b" # but there is another letter
                assert_version "1:1.2.3", GREATER, "1.2.4" # epoch rocks
                assert_version "1:1.2.3", LESS, "1:1.2.4" # bigger anyway
                assert_version "1.2a+~bCd3", LESS, "1.2a++" # tilde doesn't rock
                assert_version "1.2a+~bCd3", GREATER, "1.2a+~" # but first is longer!
                assert_version "5:2", GREATER, "304-2" # epoch rocks
                assert_version "5:2", LESS, "304:2" # so big epoch?
                assert_version "25:2", GREATER, "3:2" # 25 > 3, obviously
                assert_version "1:2:123", LESS, "1:12:3" # 12 > 2
                assert_version "1.2-5", LESS, "1.2-3-5" # 1.2 < 1.2-3
                assert_version "5.10.0", GREATER, "5.005" # preceding zeroes don't matters
                assert_version "3a9.8", LESS, "3.10.2" # letters are before all letter symbols
                assert_version "3a9.8", GREATER, "3~10" # but after the tilde
                assert_version "1.4+OOo3.0.0~", LESS, "1.4+OOo3.0.0-4" # another tilde check
                assert_version "2.4.7-1", LESS, "2.4.7-z" # revision comparing
                assert_version "1.002-1+b2", GREATER, "1.00" # whatever...
            end
        end
    end
end
