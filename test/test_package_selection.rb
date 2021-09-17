require "autoproj/test"

module Autoproj
    describe PackageSelection do
        before do
            @sel = PackageSelection.new
        end

        it "is empty on creation" do
            assert @sel.empty?
        end

        describe "#select" do
            it "registers a set of source packages" do
                @sel.select("because_of_this", %w[pkg1 pkg2])
                assert_equal %w[pkg1 pkg2], @sel.each_source_package_name.to_a
                assert_equal [], @sel.each_osdep_package_name.to_a
            end
            it "registers a selected osdep package" do
                @sel.select("because_of_this", %w[pkg1 pkg2], osdep: true)
                assert_equal [], @sel.each_source_package_name.to_a
                assert_equal %w[pkg1 pkg2], @sel.each_osdep_package_name.to_a
            end
            it "registers why a package was selected" do
                @sel.select("because_of_this", %w[pkg1 pkg2])
                assert_equal ["because_of_this"], @sel.selection["pkg1"].to_a
                assert_equal ["because_of_this"], @sel.selection["pkg2"].to_a
            end
            it "registers what matched a given selection" do
                @sel.select("because_of_this", %w[pkg1 pkg2])
                assert Set["pkg1", "pkg2"], @sel.match_for("because_of_this")
            end
            it "registers a non-weak match by default" do
                @sel.select("because_of_this", %w[pkg1 pkg2])
                refute @sel.weak_dependencies["because_of_this"]
            end
            it "records that the selection is weak" do
                @sel.select("because_of_this", %w[pkg1 pkg2], weak: true)
                assert @sel.weak_dependencies["because_of_this"]
            end
            it "treats a last argument as the 'weak' flag (compat)" do
                @sel.select("because_of_this", %w[pkg1 pkg2], true)
                assert @sel.weak_dependencies["because_of_this"]
            end
        end

        describe "#all_selected_source_packages" do
            before do
                @ws = ws_create
                @pkg1 = ws_define_package :cmake, "pkg1"
                @pkg2 = ws_define_package :cmake, "pkg2"
                @pkg1.depends_on @pkg2
            end

            it "returns the set of source packages and their dependencies" do
                @sel.select("pkg1", "pkg1")
                assert_equal Set[@pkg1, @pkg2],
                             @sel.all_selected_source_packages(ws.manifest).to_set
            end

            it "does not return osdeps" do
                @sel.select("pkg1", "pkg1", osdep: true)
                assert @sel.all_selected_source_packages(ws.manifest).empty?
            end
        end

        describe "#all_selected_osdep_packages" do
            before do
                @ws = ws_create
                @pkg1 = ws_define_package :cmake, "pkg1"
                @pkg2 = ws_define_package :cmake, "pkg2"
                @pkg1.depends_on @pkg2
                @pkg1.autobuild.os_packages << "osdep1"
                @pkg2.autobuild.os_packages << "osdep2"
            end

            it "returns the set of osdep packages selected by the source packages" do
                @sel.select("pkg1", "pkg1")
                assert_equal %w[osdep1 osdep2],
                             @sel.all_selected_osdep_packages(ws.manifest).to_a.sort
            end

            it "adds any directly selected osdep package" do
                @sel.select("pkg1", "pkg1")
                @sel.select("osdep3", "osdep3", osdep: true)
                assert_equal %w[osdep1 osdep2 osdep3],
                             @sel.all_selected_osdep_packages(ws.manifest).to_a.sort
            end
        end
    end
end
