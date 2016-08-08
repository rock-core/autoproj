require 'autoproj/test'
require 'autoproj/cli/base'
module Autoproj
    module CLI
        describe Base do
            describe "#resolve_user_selection" do
                attr_reader :ws, :base
                before do
                    @ws = ws_create
                    @base = Base.new(ws)
                end
                after do
                    Autoproj.verbose = false
                end

                describe "empty user selection" do
                    it "returns all the selected packages if called without a user selection" do
                        ws_add_package_to_layout :cmake, 'pkg0'
                        ws_add_package_to_layout :cmake, 'pkg1'
                        selection, non_resolved = base.resolve_user_selection([]) 
                        assert_equal ['pkg0', 'pkg1'], selection.each_source_package_name.to_a.sort
                        assert_equal [], non_resolved
                    end
                    it "displays the packages to be installed if verbose is set" do
                        Autoproj.verbose = true
                        ws_add_package_to_layout :cmake, 'pkg0'
                        ws_add_package_to_layout :cmake, 'pkg1'
                        out, err = capture_subprocess_io do
                            base.resolve_user_selection([]) 
                        end
                        assert_equal ["selected packages: pkg0, pkg1", ""], [out.strip, err.strip]
                    end
                end

                describe "explicit user selection" do
                    it "uses the manifest to resolve the user strings into package names" do
                        user_selection = flexmock(empty?: false)
                        user_selection.should_receive(:to_set).and_return(user_selection)
                        flexmock(ws.manifest).should_receive(:expand_package_selection).
                            once.with(user_selection, Hash).
                            and_return([expanded_selection = flexmock, []])
                        assert_equal [expanded_selection, []], base.resolve_user_selection(user_selection) 
                    end
                    it "displays the packages to be installed if verbose is set" do
                        Autoproj.verbose = true
                        ws_add_package_to_layout :cmake, 'pkg0'
                        ws_add_package_to_layout :cmake, 'pkg1'
                        out, err = capture_subprocess_io do
                            base.resolve_user_selection(['pkg0']) 
                        end
                        assert_equal ["selected packages: pkg0", ""], [out.strip, err.strip]
                    end
                end

                describe "auto-adding packages" do
                    attr_reader :package_path, :package_relative_path
                    before do
                        package_path = Pathname.new(ws.root_dir) + "path" + "to" + "package"
                        package_path.mkpath
                        @package_relative_path =
                            package_path.relative_path_from(Pathname.pwd).to_s
                        @package_path = package_path.to_s
                    end
                    it "returns selection strings which are not a valid directory" do
                        _, non_resolved = base.resolve_user_selection(['non_resolved']) 
                        assert_equal Set['non_resolved'], non_resolved
                    end
                    it "returns selection strings for packages that cannot be autodetected as a package" do
                        _, non_resolved = base.resolve_user_selection([package_relative_path]) 
                        assert_equal Set[package_relative_path], non_resolved
                    end
                    it "defines and auto-adds a package if the selection string is a path to a package" do
                        flexmock(Autoproj).should_receive(:package_handler_for).
                            with(package_path).
                            and_return(['cmake_package', package_path])
                        selection = nil
                        out, err = capture_subprocess_io do
                            selection, _ = base.resolve_user_selection([package_relative_path]) 
                        end
                        assert_equal "auto-adding #{package_path} using the cmake package handler", out.strip
                        assert_equal "", err
                        assert_equal ['path/to/package'], selection.each_source_package_name.to_a
                        autobuild_package = ws.manifest.find_autobuild_package('path/to/package')
                        assert_kind_of Autobuild::CMake, autobuild_package
                        assert_equal package_path, autobuild_package.srcdir
                    end
                end
            end
        end
    end
end

