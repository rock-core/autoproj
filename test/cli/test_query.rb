require "autoproj/test"
require "autoproj/cli/query"

module Autoproj
    module CLI
        describe Query do
            attr_reader :cli, :installation_manifest

            before do
                ws_create
                @cli = Query.new(ws)
                flexmock(cli).should_receive(:initialize_and_load)
            end

            describe "#find_all_matches" do
                it "returns all packages matching the query" do
                    base_types = ws_add_package_to_layout :cmake, "base/types"
                    base_cmake = ws_add_package_to_layout :cmake, "base/cmake"
                    assert_equal [[Autoproj::Query::PARTIAL, base_cmake], [Autoproj::Query::PARTIAL, base_types]],
                                 cli.find_all_matches(Autoproj::Query.parse("name~base"),
                                                      [base_cmake, base_types])
                    assert_equal [[Autoproj::Query::EXACT, base_cmake]],
                                 cli.find_all_matches(Autoproj::Query.parse("name=base/cmake"),
                                                      [base_cmake])
                end
            end

            describe "#run" do
                describe "osdeps: false" do
                    it "passes the 'all' query if no query string is given" do
                        flexmock(cli).should_receive(:find_all_matches)
                                     .with(Autoproj::Query::All, [])
                                     .once.and_return([])
                        cli.run([])
                    end
                    it "runs against all the selected packages by default" do
                        ws_define_package :cmake, "base/cmake"
                        base_types = ws_add_package_to_layout :cmake, "base/types"
                        flexmock(cli).should_receive(:find_all_matches)
                                     .with(any, [base_types])
                                     .once.and_return([])
                        cli.run([])
                    end
                    it "runs against all defined packages if search_all is true" do
                        base_cmake = ws_define_package :cmake, "base/cmake"
                        base_types = ws_add_package_to_layout :cmake, "base/types"
                        flexmock(cli).should_receive(:find_all_matches)
                                     .with(any, [base_cmake, base_types])
                                     .once.and_return([])
                        cli.run([], search_all: true)
                    end
                    it "filters out non-imported packages if only_present is true" do
                        base_cmake = ws_add_package_to_layout :cmake, "base/cmake"
                        base_cmake.vcs = VCSDefinition.from_raw(
                            { type: "git", url: "github.com" }
                        )
                        base_cmake.autobuild.srcdir = File.join(ws.root_dir, "base-cmake")
                        base_types = ws_add_package_to_layout :cmake, "base/types"
                        base_types.autobuild.srcdir = File.join(ws.root_dir, "base-types")

                        FileUtils.mkdir_p(base_types.autobuild.srcdir)
                        flexmock(cli).should_receive(:find_all_matches)
                                     .with(any, [base_types])
                                     .once.and_return([])
                        cli.run([], only_present: true)
                    end
                    it "parses the query and gives it to match" do
                        expected_query = ->(q) {
                            assert_equal %w[autobuild name], q.fields
                            assert_equal "test", q.value
                        }
                        flexmock(cli).should_receive(:find_all_matches)
                                     .with(expected_query, [])
                                     .once.and_return([])
                        cli.run(["name=test"])
                    end
                    it "displays the expanded format for the matching packages" do
                        base_cmake = ws_define_package :cmake, "base/cmake"
                        flexmock(cli).should_receive(:find_all_matches)
                                     .and_return([[1, base_cmake]])
                        flexmock(cli).should_receive(:format_source_package)
                                     .with("TEST FORMAT $NAME", 1, base_cmake)
                                     .and_return("formatted package")
                        out, = capture_subprocess_io do
                            cli.run([], format: "TEST FORMAT $NAME")
                        end
                        assert_equal "formatted package\n", out
                    end
                end

                describe "osdeps: true" do
                    before do
                        flexmock(cli)
                    end
                    it "passes the 'all' query if no query string is given" do
                        cli.should_receive(:find_all_matches)
                           .with(Autoproj::Query::All, [])
                           .once.and_return([])
                        cli.run([], osdeps: true)
                    end
                    it "runs against all the selected packages by default" do
                        ws_add_osdep_entries_to_layout({ "pkg" => { "os" => "test" } })
                        cli.should_receive(:find_all_matches)
                           .with(any, ["pkg"])
                           .once.and_return([])
                        cli.run([], osdeps: true)
                    end
                    it "runs against all defined packages if search_all is true" do
                        ws_define_osdep_entries({ "pkg1" => { "os" => "test" } })
                        ws_add_osdep_entries_to_layout({ "pkg2" => { "os" => "test" } })
                        cli.should_receive(:find_all_matches)
                           .with(any, %w[pkg1 pkg2])
                           .once.and_return([])
                        cli.run([], search_all: true, osdeps: true)
                    end
                    it "parses the query and gives it to match" do
                        expected_query = ->(q) {
                            assert_equal ["name"], q.fields
                            assert_equal "test", q.value
                        }
                        cli.should_receive(:find_all_matches)
                           .with(expected_query, [])
                           .once.and_return([])
                        cli.run(["name=test"], osdeps: true)
                    end
                    it "displays the expanded format for the matching packages" do
                        ws_add_osdep_entries_to_layout({ "pkg" => { "os" => "test" } })
                        cli.should_receive(:find_all_matches)
                           .and_return([[1, "pkg"]])
                        cli.should_receive(:format_osdep_package)
                           .with("TEST FORMAT $NAME", 1, "pkg", nil, nil)
                           .and_return("formatted package")
                        out, = capture_subprocess_io do
                            cli.run([], format: "TEST FORMAT $NAME", osdeps: true)
                        end
                        assert_equal "formatted package\n", out
                    end
                    it "flattens the handlers if the format contains the HANDLER key" do
                        ws_add_osdep_entries_to_layout({ "pkg" => { "os" => %w[test1 test2], "os_indep" => "test3" } })
                        cli.should_receive(:find_all_matches)
                           .and_return([[1, "pkg"]])
                        cli.should_receive(:format_osdep_package)
                           .with("TEST FORMAT $NAME $HANDLER", 1, "pkg", "os", nil)
                           .pass_thru
                        cli.should_receive(:format_osdep_package)
                           .with("TEST FORMAT $NAME $HANDLER", 1, "pkg", "os_indep", nil)
                           .pass_thru
                        out, = capture_subprocess_io do
                            cli.run([], format: "TEST FORMAT $NAME $HANDLER", osdeps: true)
                        end
                        assert_equal <<-EOMSG, out
TEST FORMAT pkg os
TEST FORMAT pkg os_indep
                        EOMSG
                    end
                    it "flattens the handlers and packages if the format contains the REAL_PACKAGE key" do
                        ws_add_osdep_entries_to_layout({ "pkg" => { "os" => %w[test1 test2], "os_indep" => "test3" } })
                        cli.should_receive(:find_all_matches)
                           .and_return([[1, "pkg"]])
                        cli.should_receive(:format_osdep_package)
                           .with("TEST FORMAT $NAME $HANDLER $REAL_PACKAGE", 1, "pkg", "os", "test1")
                           .pass_thru
                        cli.should_receive(:format_osdep_package)
                           .with("TEST FORMAT $NAME $HANDLER $REAL_PACKAGE", 1, "pkg", "os", "test2")
                           .pass_thru
                        cli.should_receive(:format_osdep_package)
                           .with("TEST FORMAT $NAME $HANDLER $REAL_PACKAGE", 1, "pkg", "os_indep", "test3")
                           .pass_thru
                        out, = capture_subprocess_io do
                            cli.run([], format: "TEST FORMAT $NAME $HANDLER $REAL_PACKAGE", osdeps: true)
                        end
                        assert_equal <<-EOMSG, out
TEST FORMAT pkg os test1
TEST FORMAT pkg os test2
TEST FORMAT pkg os_indep test3
                        EOMSG
                    end
                end
            end

            describe "#format_source_package" do
                it "expands the fields in the format string to the package's values" do
                    package = ws_define_package :cmake, "base/cmake"
                    srcdir = File.join(ws.root_dir, "src")
                    builddir = File.join(ws.root_dir, "build")
                    prefix = File.join(ws.root_dir, "prefix")
                    package.autobuild.srcdir = srcdir
                    package.autobuild.builddir = builddir
                    package.autobuild.prefix = prefix
                    package.vcs = VCSDefinition.from_raw({ type: "local", url: "/test" })

                    expected = "base/cmake #{srcdir} #{builddir} #{prefix} 0 /test false"
                    actual = cli.format_source_package(
                        "$NAME $SRCDIR $BUILDDIR $PREFIX $PRIORITY "\
                        "$URL $PRESENT", 0, package
                    )
                    assert_equal expected, actual
                end

                it "ignores if a package does not have a #builddir" do
                    package = ws_define_package :cmake, "base/cmake"
                    package.autobuild.srcdir = srcdir = File.join(ws.root_dir, "src")
                    flexmock(package.autobuild).should_receive(:respond_to?).with(:builddir).and_return(false)
                    flexmock(package.autobuild).should_receive(:builddir).never
                    package.autobuild.prefix = prefix = File.join(ws.root_dir, "prefix")
                    package.vcs = VCSDefinition.from_raw(type: "local", url: "/test")
                    assert_equal "base/cmake #{srcdir} #{prefix} 0 /test false",
                                 cli.format_source_package("$NAME $SRCDIR $PREFIX $PRIORITY $URL $PRESENT",
                                                           0, package)
                end

                it "raises if BUILDDIR is used on packages that don't have it" do
                    package = ws_define_package :cmake, "base/cmake"
                    package.autobuild.srcdir = File.join(ws.root_dir, "src")
                    package.autobuild.builddir = File.join(ws.root_dir, "build")
                    flexmock(package.autobuild).should_receive(:respond_to?).with(:builddir).and_return(false)
                    package.autobuild.prefix = File.join(ws.root_dir, "prefix")
                    package.vcs = VCSDefinition.from_raw(type: "local", url: "/test")
                    exception = assert_raises(ArgumentError) do
                        cli.format_source_package("$NAME $SRCDIR $BUILDDIR $PREFIX $PRIORITY $URL $PRESENT",
                                                  0, package)
                    end
                    assert_equal "cannot find a definition for $BUILDDIR", exception.message
                end
            end
        end
    end
end
