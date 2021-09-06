require "autoproj/test"
require "autoproj/ops/configuration"

module Autoproj
    module Ops
        describe Configuration do
            attr_reader :ops

            def mock_package_set(name, create: false, **vcs)
                vcs = VCSDefinition.from_raw(vcs)
                raw_local_dir = File.join(make_tmpdir, "package_set")
                flexmock(PackageSet).should_receive(:name_of).with(any, vcs, any).
                    and_return(name).by_default
                flexmock(PackageSet).should_receive(:raw_local_dir_of).with(any, vcs).
                    and_return(raw_local_dir).by_default
                if create
                    FileUtils.mkdir_p raw_local_dir
                    File.open(File.join(raw_local_dir, "source.yml"), "w") do |io|
                        YAML.dump(Hash["name" => name], io)
                    end
                end
                [vcs, raw_local_dir]
            end

            def make_root_package_set(*package_sets)
                root_package_set = ws.manifest.main_package_set
                package_sets.each do |vcs|
                    root_package_set.add_raw_imported_set vcs
                end
                root_package_set
            end

            before do
                ws = ws_create
                @ops = Autoproj::Ops::Configuration.new(ws)
                flexmock(@ops)
                Autobuild.silent = true
            end

            describe "#sort_package_sets_by_import_order" do
                it "should handle standalone package sets that are both explicit and dependencies of other package sets gracefully (issue#30)" do
                    pkg_set0 = flexmock("set0", imports: [], explicit?: true)
                    pkg_set1 = flexmock("set1", imports: [pkg_set0], explicit?: true)
                    root_pkg_set = flexmock("root", imports: [pkg_set0, pkg_set1], explicit?: true)
                    assert_equal [pkg_set0, pkg_set1, root_pkg_set],
                        ops.sort_package_sets_by_import_order([root_pkg_set, pkg_set1, pkg_set0], root_pkg_set)
                end
            end

            describe "#load_and_update_package_sets" do
                it "applies the package set overrides using the pkg_set:repository_id keys" do
                    package_set_dir = File.join(ws.root_dir, "package_set")
                    root_package_set = ws.manifest.main_package_set
                    root_package_set.add_raw_imported_set(
                        VCSDefinition.from_raw({ "type" => "local", "url" => "/test" })
                    )
                    root_package_set.add_overrides_entry(
                        "pkg_set:local:/test",
                        { "url" => package_set_dir }
                    )
                    FileUtils.mkdir_p package_set_dir
                    File.open(File.join(package_set_dir, "source.yml"), "w") do |io|
                        YAML.dump(Hash["name" => "imported_package_set"], io)
                    end
                    ops.load_and_update_package_sets(root_package_set)
                end

                it "passes a failure to update" do
                    test_vcs, = mock_package_set "test", type: "git", url: "/test",
                                                           create: true
                    ops.should_receive(:update_remote_package_set).
                        with(test_vcs, Hash).once.and_raise(e_klass = Class.new(RuntimeError))
                    root_package_set = make_root_package_set(test_vcs)

                    assert_raises(e_klass) do
                        ops.load_and_update_package_sets(root_package_set)
                    end
                end

                it "passes a failure to checkout" do
                    test_vcs, = mock_package_set "test", type: "git", url: "/test"
                    ops.should_receive(:update_remote_package_set).
                        with(test_vcs, Hash).once.and_raise(e_klass = Class.new(RuntimeError))
                    root_package_set = make_root_package_set(test_vcs)

                    assert_raises(e_klass) do
                        ops.load_and_update_package_sets(root_package_set)
                    end
                end

                describe "keep_going: true" do
                    it "does pass an interrupt" do
                        mock_package_set "test", type: "git", url: "/test"
                        test0_vcs, = mock_package_set(
                            "test0", type: "git", url: "/test0", create: true
                        )
                        test1_vcs, = mock_package_set(
                            "test1", type: "git", url: "/test1", create: true
                        )
                        ops.should_receive(:update_remote_package_set)
                           .with(test0_vcs, Hash).once
                           .and_raise(Interrupt)
                        ops.should_receive(:update_remote_package_set)
                           .with(test1_vcs, Hash).never
                        root_package_set = make_root_package_set(test0_vcs, test1_vcs)

                        assert_raises(Interrupt) do
                            ops.load_and_update_package_sets(
                                root_package_set, keep_going: true
                            )
                        end
                    end
                    it "still raises if a checkout failed" do
                        test_vcs, = mock_package_set "test", type: "git", url: "/test"
                        ops.should_receive(:update_remote_package_set).
                            with(test_vcs, Hash).once.and_raise(e_klass = Class.new(RuntimeError))
                        root_package_set = make_root_package_set(test_vcs)

                        assert_raises(e_klass) do
                            ops.load_and_update_package_sets(root_package_set, keep_going: true)
                        end
                    end
                    it "collects the errors and raises an ImportFailed at the end of import" do
                        test0_vcs, = mock_package_set "test0", type: "git", url: "/test0",
                            create: true
                        test1_vcs, = mock_package_set "test1", type: "git", url: "/test1",
                            create: true
                        ops.should_receive(:update_remote_package_set).
                            with(test0_vcs, Hash).once.
                            and_raise(error0 = Class.new(RuntimeError))
                        ops.should_receive(:update_remote_package_set).
                            with(test1_vcs, Hash).once.
                            and_raise(error1 = Class.new(RuntimeError))
                        root_package_set = make_root_package_set(test0_vcs, test1_vcs)

                        _, e = ops.load_and_update_package_sets(root_package_set, keep_going: true)
                        assert_equal 2, e.size
                        assert_kind_of error0, e[0]
                        assert_kind_of error1, e[1]
                    end
                    it "loads even the failed package sets" do
                    end
                end

                describe "handling of package sets with the same name" do
                    attr_reader :pkg_set_0, :pkg_set_1, :root_package_set
                    before do
                        flexmock(ws.os_package_installer).should_receive(:install)
                        @pkg_set_0 = ws_create_git_package_set "test.pkg.set"
                        @pkg_set_1 = ws_create_git_package_set "test.pkg.set"
                        @root_package_set = ws.manifest.main_package_set
                        root_package_set.add_raw_imported_set \
                            VCSDefinition.from_raw("type" => "git", "url" => pkg_set_0)
                    end

                    it "uses only the first" do
                        root_package_set.add_raw_imported_set \
                            VCSDefinition.from_raw("type" => "git", "url" => pkg_set_1)
                        package_sets, = ops.load_and_update_package_sets(root_package_set)
                        assert_equal 2, package_sets.size
                        assert_same root_package_set, package_sets.first
                        assert_equal pkg_set_0, package_sets.last.vcs.url
                    end

                    it "ensures that the user link in remotes/ points to the first match" do
                        root_package_set.add_raw_imported_set \
                            VCSDefinition.from_raw("type" => "git", "url" => pkg_set_1)
                        package_sets, = ops.load_and_update_package_sets(root_package_set)
                        assert_equal pkg_set_0, package_sets[1].vcs.url
                        assert_equal package_sets[1].raw_local_dir, File.readlink(
                            File.join(ws.config_dir, "remotes", "test.pkg.set"))
                    end

                    it "redirects package sets that import a colliding package set to the first" do
                        importing_pkg_set = ws_create_git_package_set "importing.pkg.set",
                            "imports" => Array["type" => "git", "url" => pkg_set_1]
                        root_package_set.add_raw_imported_set \
                            VCSDefinition.from_raw("type" => "git", "url" => importing_pkg_set)
                        package_sets, = ops.load_and_update_package_sets(root_package_set)

                        assert_equal 3, package_sets.size
                        assert_same  root_package_set, package_sets[0]
                        assert_equal pkg_set_0, package_sets[1].vcs.url

                        imported  = package_sets[1]
                        importing = package_sets[2]
                        assert_equal importing_pkg_set, importing.vcs.url
                        assert imported.imported_from.include?(importing)
                        assert importing.imports.include?(imported)
                    end

                    it "redirects following imports to the first as well" do
                        importing_pkg_set = ws_create_git_package_set(
                            "importing.pkg.set",
                            "imports" => Array["type" => "git", "url" => pkg_set_1]
                        )
                        other_importing_pkg_set = ws_create_git_package_set(
                            "other_importing.pkg.set",
                            "imports" => Array["type" => "git", "url" => pkg_set_1]
                        )
                        root_package_set.add_raw_imported_set(
                            VCSDefinition.from_raw(
                                { "type" => "git", "url" => importing_pkg_set }
                            )
                        )
                        root_package_set.add_raw_imported_set(
                            VCSDefinition.from_raw(
                                { "type" => "git", "url" => other_importing_pkg_set }
                            )
                        )
                        package_sets, = ops.load_and_update_package_sets(root_package_set)

                        assert_equal 4, package_sets.size
                        assert_same  root_package_set, package_sets[0]
                        assert_equal pkg_set_0, package_sets[1].vcs.url
                        assert_equal importing_pkg_set, package_sets[2].vcs.url

                        imported = package_sets[1]
                        other_importing = package_sets[3]
                        assert_equal other_importing_pkg_set, other_importing.vcs.url
                        assert imported.imported_from.include?(other_importing)
                        assert other_importing.imports.include?(imported)
                    end
                end
            end

            describe "#update_remote_package_set" do
                before do
                    flexmock(ws.os_package_installer).should_receive(:install).by_default
                end

                it "installs the vcs' osdep" do
                    vcs, _raw_local_dir = mock_package_set("test", type: "git", url: "/whatever")
                    flexmock(ws.os_package_installer).should_receive(:install).once.
                        with(["git"], all: nil)
                    ops.should_receive(:update_configuration_repository).once
                    ops.update_remote_package_set(vcs, checkout_only: false)
                end

                it "does call the import if checkout_only is set but the package set is not present" do
                    vcs, raw_local_dir = mock_package_set("test", type: "git", url: "/whatever")
                    ops.should_receive(:update_configuration_repository).once.
                        with(vcs, "test", raw_local_dir, Hash)
                    ops.update_remote_package_set(vcs, checkout_only: false)
                end

                it "does call the import if checkout_only is not set and the package set is present" do
                    vcs, raw_local_dir = mock_package_set("test", type: "git", url: "/whatever")
                    FileUtils.mkdir_p(raw_local_dir)
                    ops.should_receive(:update_configuration_repository).once
                    ops.update_remote_package_set(vcs, checkout_only: false)
                end

                it "returns right away if checkout_only is set and the remote is checked out" do
                    vcs, raw_local_dir = mock_package_set("test", type: "git", url: "/whatever")
                    FileUtils.mkdir_p raw_local_dir
                    ops.should_receive(:update_configuration_repository).never
                    ops.update_remote_package_set(vcs, checkout_only: true)
                end

                it "successfully updates an invalid but already-checked-out package whose update fixes the issue" do
                    vcs, raw_local_dir = mock_package_set("test", type: "git", url: "/whatever")
                    FileUtils.mkdir_p(raw_local_dir)
                    FileUtils.touch File.join(raw_local_dir, "source.yml")
                    ops.should_receive(:update_configuration_repository).once.and_return do
                        File.open(File.join(raw_local_dir, "source.yml"), "w") do |io|
                            YAML.dump(Hash["name" => "test"], io)
                        end
                    end
                    ops.update_remote_package_set(vcs, checkout_only: false)
                end
            end

            describe "#update_package_sets" do
                it "has only one main package set in the resulting manifest" do
                    package_set_dir = File.join(ws.root_dir, "package_set")
                    root_package_set = ws.manifest.main_package_set
                    root_package_set.add_raw_imported_set VCSDefinition.from_raw(
                        { "type" => "local", "url" => package_set_dir }
                    )
                    FileUtils.mkdir_p package_set_dir
                    File.open(File.join(package_set_dir, "source.yml"), "w") do |io|
                        YAML.dump(Hash["name" => "imported_package_set"], io)
                    end
                    ops.update_package_sets
                    package_sets = ws.manifest.each_package_set.to_a
                    assert_equal 2, package_sets.size
                    assert_same root_package_set, package_sets[1]

                    expected = VCSDefinition.from_raw(
                        { "type" => "local", "url" => package_set_dir }
                    )
                    assert_equal expected, package_sets[0].vcs
                end
            end

            describe "#update_main_configuration" do
                it "updates the manifest's repository" do
                    manifest_vcs, only_local, reset, retry_count = flexmock, flexmock, flexmock, flexmock
                    ws.manifest.vcs = manifest_vcs
                    ops.should_receive(:update_configuration_repository).
                        once.with(manifest_vcs, "autoproj main configuration", ws.config_dir,
                                  only_local: only_local, reset: reset, retry_count: retry_count)
                    assert_equal [], ops.update_main_configuration(only_local: only_local, reset: reset, retry_count: retry_count)
                end
                it "does nothing if checkout_only is true and the config dir is already present" do
                    ops.should_receive(:update_configuration_repository).never
                    assert_equal [], ops.update_main_configuration(checkout_only: true)
                end
                it "does update if checkout_only is true but the config dir is not yet present" do
                    FileUtils.rm_rf ws.config_dir
                    ops.should_receive(:update_configuration_repository).once
                    assert_equal [], ops.update_main_configuration(checkout_only: true)
                end
                it "returns the list of update errors if keep_going is true" do
                    ops.should_receive(:update_configuration_repository).
                        and_raise(error = Class.new(Exception).new)
                    assert_equal [error], ops.update_main_configuration(keep_going: true)
                end
                it "passes Interrupt even if keep_going is true" do
                    ops.should_receive(:update_configuration_repository).
                        and_raise(Interrupt)
                    assert_raises(Interrupt) do
                        ops.update_main_configuration(keep_going: true)
                    end
                end
                it "passes exceptions if keep_going is false" do
                    ops.should_receive(:update_configuration_repository).
                        and_raise(error = Class.new(Exception).new)
                    assert_raises(error.class) do
                        ops.update_main_configuration
                    end
                end
            end

            describe "#update_configuration" do
                it "does not import the main configuration if it does not need to" do
                    flexmock(ws.manifest.vcs).should_receive(:needs_import?).
                        and_return(false)
                    ops.should_receive(:update_main_configuration).never
                    ops.update_configuration
                end
                it "imports the main configuration if it needs it" do
                    flexmock(ws.manifest.vcs).should_receive(:needs_import?).
                        and_return(true)
                    ops.should_receive(:update_main_configuration).once.
                        and_return([])
                    ops.should_receive(:report_import_failure).never
                    ops.update_configuration
                end
                it "reports the import failures" do
                    flexmock(ws.manifest.vcs).should_receive(:needs_import?).
                        and_return(true)
                    ops.should_receive(:update_main_configuration).once.
                        and_return([e = flexmock])
                    ops.should_receive(:report_import_failure).
                        with("main configuration", e).once
                    assert_raises(ImportFailed) do
                        ops.update_configuration
                    end
                end
                it "imports the main configuration if it needs it" do
                    flexmock(ws.manifest.vcs).should_receive(:needs_import?).
                        and_return(true)
                    ops.should_receive(:update_main_configuration).once.
                        and_return([])
                    ops.update_configuration
                end
                it "passes an import failure if keep_going is false" do
                    flexmock(ws.manifest.vcs).should_receive(:needs_import?).
                        and_return(true)
                    ops.should_receive(:update_configuration_repository).once.
                        and_raise(e_klass = Class.new(RuntimeError))
                    ops.should_receive(:update_package_sets).never
                    assert_raises(e_klass) do
                        ops.update_configuration(keep_going: false)
                    end
                end

                describe "keep_going: true" do
                    before do
                        flexmock(ws.manifest.vcs).should_receive(:needs_import?).
                            and_return(true)
                    end
                    it "attempts to update and load the package sets after a main configuration import failure" do
                        ops.should_receive(:update_main_configuration).once.
                            with(hsh(keep_going: true)).and_return([flexmock])
                        ops.should_receive(:update_package_sets).once.
                            pass_thru
                        ops.should_receive(:load_package_set_information).once
                        assert_raises(ImportFailed) do
                            ops.update_configuration(keep_going: true)
                        end
                    end
                    it "reports main configuration errors" do
                        ops.should_receive(:update_main_configuration).once.
                            and_return([main_import_failure = flexmock])
                        e = assert_raises(ImportFailed) do
                            ops.update_configuration(keep_going: true)
                        end
                        assert_equal [main_import_failure], e.original_errors
                    end
                    it "reports package set update errors" do
                        ops.should_receive(:update_main_configuration).once.and_return([])
                        ops.should_receive(:update_package_sets).once.
                            with(hsh(keep_going: true)).and_return([failure = flexmock])
                        e = assert_raises(ImportFailed) do
                            ops.update_configuration(keep_going: true)
                        end
                        assert_equal [failure], e.original_errors
                    end
                    it "aggregates the package set errors with the main configuration errors" do
                        ops.should_receive(:update_configuration_repository).once.
                            and_raise(e_klass = Class.new(RuntimeError))
                        ops.should_receive(:update_package_sets).once.
                            and_return([package_set_error = flexmock])
                        e = assert_raises(ImportFailed) do
                            ops.update_configuration(keep_going: true)
                        end
                        assert_equal 2, e.original_errors.size
                        assert_kind_of e_klass, e.original_errors[0]
                        assert_equal package_set_error, e.original_errors[1]
                    end
                end
            end

            describe "#load_no_packages_layout" do
                it "load no layout" do
                    FileUtils.mkdir_p ws.config_dir
                    manifest_path = File.join(ws.config_dir, "manifest")
                    FileUtils.touch(manifest_path)
                    ws.manifest.load manifest_path
                    refute ws.manifest.has_layout?
                end

                it "load empty layout entry" do
                    FileUtils.mkdir_p ws.config_dir
                    manifest_path = File.join(ws.config_dir, "manifest")
                    File.open(manifest_path, "w") do |io|
                        YAML.dump(Hash["layout" => [nil]], io)
                    end
                    flexmock(Autoproj).should_receive(:warn).
                        with("There is an empty entry in your layout in "\
                            "#{manifest_path}. All empty entries are ignored.").
                        once
                    ws.manifest.load manifest_path
                    assert ws.manifest.has_layout?
                end
            end

            describe "#load_package_set_information" do
                before do
                    FileUtils.mkdir_p ws.config_dir
                    FileUtils.touch(manifest_path = File.join(ws.config_dir, "manifest"))
                    ws.manifest.load manifest_path
                    FileUtils.touch File.join(ws.config_dir, "test.autobuild")
                    File.open(File.join(ws.config_dir, "test.osdeps"), "w") do |io|
                        YAML.dump(Hash.new, io)
                    end
                    File.open(File.join(ws.config_dir, "test.osrepos"), "w") do |io|
                        YAML.dump([], io)
                    end
                    File.open(File.join(ws.config_dir, "overrides.yml"), "w") do |io|
                        YAML.dump(Hash["version_control" => Array.new, "overrides" => Array.new], io)
                    end
                    ws.load_config
                end

                def add_in_osdeps(entry)
                    test_osdeps = File.join(ws.config_dir, "test.osdeps")
                    current = YAML.load(File.read(test_osdeps))
                    File.open(test_osdeps, "w") do |io|
                        YAML.dump(current.merge!(entry), io)
                    end
                end

                def add_in_packages(lines)
                    File.open(File.join(ws.config_dir, "test.autobuild"), "a") do |io|
                        io.puts lines
                    end
                end

                def add_version_control(package_name, type: "local", url: package_name, **vcs)
                    overrides_yml = YAML.load(File.read(File.join(ws.config_dir, "overrides.yml")))
                    overrides_yml["version_control"] << Hash[
                        package_name =>
                            vcs.merge(type: type, url: url)
                    ]
                    File.open(File.join(ws.config_dir, "overrides.yml"), "w") do |io|
                        io.write YAML.dump(overrides_yml)
                    end
                    ws.manifest.main_package_set.load_description_file
                end

                it "loads the osdep files" do
                    flexmock(ws.manifest.each_package_set.first).
                        should_receive(:load_osdeps).
                        with(File.join(ws.config_dir, "test.osdeps"), Hash).
                        at_least.once.and_return(osdep = flexmock)
                    flexmock(ws.os_package_resolver).
                        should_receive(:merge).with(osdep).at_least.once

                    ops.load_package_set_information
                end
                it "loads the osrepos files" do
                    flexmock(ws.manifest.each_package_set.first)
                        .should_receive(:load_osrepos)
                        .with(File.join(ws.config_dir, "test.osrepos"))
                        .at_least.once.and_return(osrepo = flexmock)
                    flexmock(ws.os_repository_resolver)
                        .should_receive(:merge).with(osrepo).at_least.once

                    ops.load_package_set_information
                end
                it "excludes osdeps that are not available locally" do
                    add_in_osdeps Hash["test" => "nonexistent"]
                    ops.load_package_set_information
                    assert ws.manifest.excluded?("test")
                end
                it "excludes osdeps that are not available locally" do
                    add_in_osdeps Hash["test" => Hash["another_os" => "test"]]
                    ops.load_package_set_information
                    assert ws.manifest.excluded?("test")
                end
                it "does not exclude osdeps that have a definition" do
                    add_in_osdeps Hash["test" => Hash["test_os_family" => "test"]]
                    ops.load_package_set_information
                    refute ws.manifest.excluded?("test")
                end
                it "excludes osdeps if the local OS is not known" do
                    add_in_osdeps Hash["test" => Hash["test_os_family" => "test"]]
                    ws.os_package_resolver.operating_system = [[], []]
                    ops.load_package_set_information
                    assert ws.manifest.excluded?("test")
                end
                it "does not exclude osdeps for which a source package with the same name exists" do
                    add_in_osdeps Hash["test" => "nonexistent"]
                    add_in_packages 'cmake_package "test"'
                    add_version_control "test"
                    ops.load_package_set_information
                    refute ws.manifest.excluded?("test")
                end
                it "does not exclude osdeps for which an osdep override exists" do
                    add_in_osdeps Hash["test" => "nonexistent"]
                    add_in_packages 'cmake_package "mapping_test"'
                    add_version_control "mapping_test"
                    add_in_packages 'Autoproj.add_osdeps_overrides "test", package: "mapping_test"'
                    ops.load_package_set_information
                    refute ws.manifest.excluded?("test")
                end

                it "resolves a mainline argument given as string" do
                    pkg_set = ws_create_local_package_set("pkg_set", make_tmpdir)
                    flexmock(ws.manifest).should_receive(:load_importers).with(mainline: pkg_set).once
                    ops.load_package_set_information(mainline: "pkg_set")
                end

                it "passes on a mainline argument given as object" do
                    pkg_set = ws_create_local_package_set("pkg_set", make_tmpdir)
                    flexmock(ws.manifest).should_receive(:load_importers).with(mainline: pkg_set).once
                    ops.load_package_set_information(mainline: pkg_set)
                end
            end

            describe "#auto_add_packages_from_layout" do
                it "ignores the names of existing packages" do
                    ws_add_package_to_layout :cmake, "pkg"
                    ops.should_receive(:auto_add_package).never
                    ops.auto_add_packages_from_layout
                end
                it "ignores the names of existing metapackages" do
                    pkg = ws_define_package :cmake, "pkg"
                    ws_add_metapackage_to_layout "metapkg", pkg
                    ops.should_receive(:auto_add_package).never
                    ops.auto_add_packages_from_layout
                end
                it "ignores non-checked-out 'packages'" do
                    ws.manifest.clear_layout # to make sure that the manifest uses a layout
                    ws.manifest.normalized_layout["tools/test"] = "/"
                    ops.should_receive(:auto_add_package).never
                    ops.auto_add_packages_from_layout
                end
                it "attempts to auto-load checked out packages" do
                    ws.manifest.clear_layout # to make sure that the manifest uses a layout
                    ws.manifest.normalized_layout["tools/test"] = "/"
                    pkg_dir = File.join(ws.root_dir, "tools", "test")
                    FileUtils.mkdir_p pkg_dir
                    flexmock(Autoproj).should_receive(:package_handler_for).once.
                        with(pkg_dir).
                        and_return("cmake_package")
                    flexmock(Autoproj).should_receive(:message).once.
                        with("  auto-added tools\/test using the cmake package handler")
                    ops.auto_add_packages_from_layout
                    assert_kind_of Autobuild::CMake, ws.manifest.package_definition_by_name("tools/test").autobuild
                end
                it "warns if a package cannot be auto-added" do
                    ws.manifest.clear_layout # to make sure that the manifest uses a layout
                    ws.manifest.normalized_layout["tools/test"] = "/"
                    pkg_dir = File.join(ws.root_dir, "tools", "test")
                    FileUtils.mkdir_p pkg_dir
                    flexmock(Autoproj).should_receive(:package_handler_for).once.
                        with(pkg_dir).and_return(nil)
                    flexmock(Autoproj).should_receive(:warn).once.
                        with("cannot auto-add tools/test: unknown package type")
                    ops.auto_add_packages_from_layout
                    assert_nil ws.manifest.find_package_definition("tools/test")
                end
            end
        end
    end
end
