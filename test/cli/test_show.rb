require 'autoproj/test'
require 'autoproj/cli/show'

module Autoproj
    module CLI
        describe Show do
            attr_reader :cli
            before do
                ws_create
                @cli = CLI::Show.new(ws)
                # To avoid overriding the test fixture setup with the state on
                # disk
                flexmock(cli).should_receive(:initialize_and_load)
            end

            describe "#run" do
                describe "handling of package sets" do
                    it "displays the package set information" do
                        ws_define_package_set('rock.core')
                        flexmock(cli).should_receive(:display_package_set).with('rock.core').once
                        cli.run(['rock.core'])
                    end
                    it "does not resolve the package set to its packages" do
                        Autoproj.silent = true
                        pkg_set = ws_define_package_set('rock.core')
                        ws_define_package(:cmake, 'pkg', package_set: pkg_set)
                        flexmock(cli).should_receive(:display_package_set).with('rock.core').once
                        flexmock(cli).should_receive(:display_source_package).never
                        cli.run(['rock.core'])
                    end
                    it "does display all packages if only a package set is given" do
                        Autoproj.silent = true
                        ws_define_package_set('rock.core')
                        ws_add_package_to_layout(:cmake, 'pkg')
                        flexmock(cli).should_receive(:display_package_set).with('rock.core').once
                        flexmock(cli).should_receive(:display_source_package).never
                        cli.run(['rock.core'])
                    end
                end

                describe "handling of source packages" do
                    it "displays the source package information" do
                        Autoproj.silent = true
                        ws_define_package(:cmake, 'base/cmake')
                        flexmock(cli).should_receive(:display_source_package).
                            with('base/cmake', PackageSelection, Hash, env: false).once
                        cli.run(['base/cmake'])
                    end
                    it "passes the set of default packages to the display method" do
                        Autoproj.silent = true
                        ws_define_package(:cmake, 'base/cmake')
                        ws_add_package_to_layout(:cmake, 'base/types')
                        flexmock(cli).should_receive(:display_source_package).
                            with('base/cmake',
                                 ->(sel) { sel.each_source_package_name.find('base/types') },
                                 Hash,
                                 env: false).once
                        cli.run(['base/cmake'])
                    end
                    it "passes the reverse dependencies to the display method" do
                        Autoproj.silent = true
                        ws_define_package(:cmake, 'base/cmake')
                        flexmock(ws.manifest).should_receive(:compute_revdeps).
                            once.and_return(revdeps = flexmock)
                        flexmock(cli).should_receive(:display_source_package).
                            with('base/cmake', any, revdeps,
                                 env: false).once
                        cli.run(['base/cmake'])
                    end
                end

                describe "handling of osdep packages" do
                    it "displays the package information" do
                        ws_define_osdep_entries('base/cmake' => 'gem')
                        flexmock(cli).should_receive(:display_osdep_package).
                            with('base/cmake', PackageSelection, Hash, true).once
                        cli.run(['base/cmake'])
                    end
                    it "displays both the source and the osdep if there is a souce override" do
                        Autoproj.silent = true
                        ws_add_package_to_layout :cmake, 'base/cmake'
                        ws.manifest.add_osdeps_overrides 'base/cmake', force: true
                        ws_define_osdep_entries('base/cmake' => 'gem')
                        flexmock(cli).should_receive(:display_source_package).
                            with('base/cmake', PackageSelection, Hash, env: false).once
                        flexmock(cli).should_receive(:display_osdep_package).
                            with('base/cmake', PackageSelection, Hash, false).once
                        cli.run(['base/cmake'])
                    end
                    it "displays both the source and the osdep if the osdep is marked as nonexistent and there is a source package" do
                        Autoproj.silent = true
                        ws_add_package_to_layout :cmake, 'base/cmake'
                        ws_define_osdep_entries('base/cmake' => 'nonexistent')
                        flexmock(cli).should_receive(:display_source_package).
                            with('base/cmake', PackageSelection, Hash, env: false).once
                        flexmock(cli).should_receive(:display_osdep_package).
                            with('base/cmake', PackageSelection, Hash, false).once
                        cli.run(['base/cmake'])
                    end
                    it "passes the set of default packages to the display method" do
                        ws_define_osdep_entries('base/cmake' => 'gem')
                        ws_add_osdep_entries_to_layout('base/types' => 'gem')
                        flexmock(cli).should_receive(:display_osdep_package).
                            with('base/cmake',
                                 ->(sel) { sel.each_source_package_name.find('base/types') },
                                 Hash, true).once
                        cli.run(['base/cmake'])
                    end
                    it "passes the reverse dependencies to the display method" do
                        ws_define_osdep_entries('base/cmake' => 'gem')
                        flexmock(ws.manifest).should_receive(:compute_revdeps).
                            once.and_return(revdeps = flexmock)
                        flexmock(cli).should_receive(:display_osdep_package).
                            with('base/cmake', any, revdeps, true).once
                        cli.run(['base/cmake'])
                    end
                end
            end

            describe "#display_package_set" do
                attr_reader :pkg_set
                before do
                    Autobuild.color = false
                    @pkg_set = ws_define_package_set 'rock.core', raw_local_dir: File.join(ws.root_dir, 'dir')
                end
                after do
                    Autobuild.color = nil
                end

                def assert_displays(name, *messages, **options)
                    out, _ = capture_subprocess_io do
                        cli.display_package_set(name, **options)
                    end
                    out = out.split("\n")
                    messages.each do |msg|
                        assert_equal 1, out.count(msg), "expected output to contain '#{msg}', output is:\n\n#{out.join("\n")}"
                    end
                    out
                end
                
                it "displays the package set name" do
                    assert_displays 'rock.core', "package set rock.core"
                end
                it "warns if the package set is not checked out" do
                    assert_displays 'rock.core', "  this package set is not checked out"
                end
                it "displays the raw and user local dirs if they are different" do
                    flexmock(pkg_set).should_receive(:raw_local_dir).and_return('/raw/dir')
                    flexmock(pkg_set).should_receive(:user_local_dir).and_return('/user/dir')
                    assert_displays 'rock.core',
                        "  checkout dir: /raw/dir",
                        "  symlinked to: /user/dir"
                end
                it "displays the only one dir if the raw and user dirs are the same" do
                    flexmock(pkg_set).should_receive(:raw_local_dir).and_return('/raw/dir')
                    flexmock(pkg_set).should_receive(:user_local_dir).and_return('/raw/dir')
                    assert_displays 'rock.core', "  path: /raw/dir"
                end
                it "displays the package set VCS" do
                    flexmock(pkg_set).should_receive(:vcs).and_return(vcs = flexmock(overrides_key: nil))
                    flexmock(pkg_set).should_receive(:user_local_dir).and_return(pkg_set.raw_local_dir)
                    flexmock(cli).should_receive(:display_vcs).with(vcs).once
                    capture_subprocess_io do
                        cli.display_package_set('rock.core')
                    end
                end
                it "displays the package set's overrides key" do
                    pkg_set.vcs = VCSDefinition.from_raw('type' => 'local', 'url' => '/path')
                    assert_displays 'rock.core', '  overrides key: pkg_set:local:/path'
                end
                it "displays the package set's packages" do
                    assert_displays 'rock.core', '  does not have any packages'
                    ws_define_package :cmake, 'bbb', package_set: pkg_set
                    assert_displays 'rock.core', '  refers to 1 package', '    bbb'
                    ws_define_package :cmake, 'aaa', package_set: pkg_set
                    assert_displays 'rock.core', '  refers to 2 packages', '    aaa, bbb'
                end
                it "splits the lines at the required size" do
                    ws_define_package :cmake, 'bbb', package_set: pkg_set
                    ws_define_package :cmake, 'aaa', package_set: pkg_set
                    assert_displays 'rock.core', '  refers to 2 packages', '    aaa,', '    bbb',
                        package_per_line: 1
                end
            end

            describe "#display_osdep_package" do
                attr_reader :pkg_set
                before do
                    Autobuild.color = false
                end
                after do
                    Autobuild.color = nil
                end

                def assert_displays(name, selected, *messages)
                    flexmock(cli).should_receive(:display_common_information).
                        with(name, default_packages = flexmock, revdeps = flexmock).
                        once

                    out, _ = capture_subprocess_io do
                        cli.display_osdep_package(name, default_packages, revdeps, selected)
                    end
                    out = out.split("\n")
                    messages.each do |msg|
                        assert_equal 1, out.count(msg), "expected output to contain '#{msg}', output is:\n\n#{out.join("\n")}"
                    end
                    out
                end

                it "displays per-manager packages" do
                    ws_define_osdep_entries 'test' => 'gem'
                    assert_displays 'test', true, "  os: gem"
                end

                it "handles a non-resolvable package" do
                    ws_define_osdep_entries 'test' => 'nonexistent'
                    assert_displays 'test', false, "  there is an osdep definition for test, and it explicitely states that this package does not exist on your OS"
                end

                it "indicates if the osdep would not be used by autoproj" do
                    ws_define_osdep_entries 'test' => 'gem'
                    assert_displays 'test', false, "  is present, but won't be used by autoproj for 'test'"
                end
            end
        end
    end
end

