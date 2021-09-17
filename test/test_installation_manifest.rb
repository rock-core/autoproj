require "autoproj/test"
require "set"

module Autoproj
    describe InstallationManifest do
        before do
            ws_create
            @manifest = InstallationManifest.new
        end

        it "registers a package" do
            pkg_def = ws_define_package :cmake, "test"
            flexmock(pkg_def.autobuild, dependencies: %w[a b c])
            ws_define_package_vcs(
                pkg_def, { type: "git", url: "https://github.com/some/repo" }
            )
            ws_resolve_vcs(pkg_def)

            pkg = @manifest.add_package(pkg_def)
            assert_equal "test", pkg.name
            assert_equal "Autobuild::CMake", pkg.type
            assert_equal({ type: "git", url: "https://github.com/some/repo" },
                         pkg.vcs)
            assert_equal pkg.srcdir, pkg_def.autobuild.srcdir
            assert_equal pkg.importdir, pkg_def.autobuild.importdir
            assert_equal pkg.prefix, pkg_def.autobuild.prefix
            assert_equal pkg.builddir, pkg_def.autobuild.builddir
            assert_equal pkg.logdir, pkg_def.autobuild.logdir
            assert_equal %w[a b c], pkg.dependencies
        end

        it "registers a package set" do
            options = {} # workaround 2.6 brokenness
            ws_set = ws_define_package_set(
                "bla", VCSDefinition.from_raw({ type: "git", url: "somewhere" }),
                **options
            )

            pkg_set = @manifest.add_package_set(ws_set)
            assert_equal "bla", pkg_set.name
            assert_equal({ type: "git", url: "somewhere" }, pkg_set.vcs)
            assert_equal ws_set.raw_local_dir, pkg_set.raw_local_dir
            assert_equal ws_set.user_local_dir, pkg_set.user_local_dir
        end

        it "saves and loads packages and package sets" do
            pkg_def = ws_define_package :cmake, "test"
            flexmock(pkg_def.autobuild, dependencies: %w[a b c])
            ws_define_package_vcs(
                pkg_def, { type: "git", url: "https://github.com/some/repo" }
            )
            ws_resolve_vcs(pkg_def)

            options = {} # Workaround 2.6 brokenness
            ws_set = ws_define_package_set(
                "bla", VCSDefinition.from_raw({ type: "git", url: "somewhere" }),
                **options
            )

            @manifest.add_package_set(ws_set)
            @manifest.add_package(pkg_def)
            dir = make_tmpdir
            path = File.join(dir, "manifest.yml")
            @manifest.save path
            new_manifest = InstallationManifest.new
            new_manifest.load(path)

            pkg_set = new_manifest.find_package_set_by_name("bla")
            assert_equal "bla", pkg_set.name
            assert_equal({ type: "git", url: "somewhere" }, pkg_set.vcs)
            assert_equal ws_set.raw_local_dir, pkg_set.raw_local_dir
            assert_equal ws_set.user_local_dir, pkg_set.user_local_dir

            pkg = new_manifest.find_package_by_name("test")
            assert_equal "test", pkg.name
            assert_equal "Autobuild::CMake", pkg.type
            assert_equal({ type: "git", url: "https://github.com/some/repo" },
                         pkg.vcs)
            assert_equal pkg.srcdir, pkg_def.autobuild.srcdir
            assert_equal pkg.importdir, pkg_def.autobuild.importdir
            assert_equal pkg.prefix, pkg_def.autobuild.prefix
            assert_equal pkg.builddir, pkg_def.autobuild.builddir
            assert_equal pkg.logdir, pkg_def.autobuild.logdir
            assert_equal %w[a b c], pkg.dependencies
        end
    end
end
