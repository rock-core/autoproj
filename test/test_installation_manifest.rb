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

            pkg_def.autobuild.description = package_manifest_fixture(pkg_def.autobuild)
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

            assert_package_manifest(pkg.manifest)
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
            pkg_def.autobuild.description = package_manifest_fixture(pkg_def.autobuild)

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

            assert_package_manifest(pkg.manifest)
        end

        def package_manifest_base_fields
            {
                description: "d",
                brief_description: "brief_d",
                tags: %w[some tags],
                url: "u", license: "l", version: "v"
            }
        end

        def assert_package_manifest(obj)
            assert_kind_of InstallationManifest::Manifest, obj
            package_manifest_base_fields.each do |key, value|
                assert_equal value, obj.send(key)
            end

            assert_contact_info([%w[a_n1 a_e1], %w[a_n2 a_e2]], obj.authors)
            assert_contact_info([%w[m_n1 m_e1], %w[m_n2 m_e2]], obj.maintainers)
            assert_contact_info([%w[rm_n1 rm_e1], %w[rm_n2 rm_e2]], obj.rock_maintainers)
            assert_dependencies(
                [["p_n1", true, ["build"]], ["p_n2", false, ["runtime"]]],
                obj.dependencies
            )
        end

        def assert_dependencies(expected, actual)
            expected.zip(actual) do |(name, optional, modes), obj|
                assert_equal name, obj.name
                if optional
                    assert obj.optional
                else
                    refute obj.optional
                end
                assert_equal modes, obj.modes
            end
        end

        def assert_contact_info(expected, actual)
            assert_equal expected.size, actual.size
            expected.zip(actual) do |(e_name, e_email), obj|
                assert_equal e_name, obj.name
                assert_equal e_email, obj.email
            end
        end

        def package_manifest_fixture(autobuild)
            pkg_manifest = PackageManifest.new(autobuild)
            package_manifest_base_fields.each do |k, v|
                pkg_manifest.send("#{k}=", v)
            end
            pkg_manifest.authors = make_contact_list(%w[a_n1 a_e1], %w[a_n2 a_e2])
            pkg_manifest.maintainers = make_contact_list(%w[m_n1 m_e1], %w[m_n2 m_e2])
            pkg_manifest.rock_maintainers =
                make_contact_list(%w[rm_n1 rm_e1], %w[rm_n2 rm_e2])
            pkg_manifest.dependencies.concat(
                make_dependencies(["p_n1", true, ["build"]], ["p_n2", false, ["runtime"]])
            )
            pkg_manifest
        end

        def make_contact_list(*data)
            data.map { |values| PackageManifest::ContactInfo.new(*values) }
        end

        def make_dependencies(*data)
            data.map { |values| PackageManifest::Dependency.new(*values) }
        end
    end
end
