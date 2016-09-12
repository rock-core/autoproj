require 'autoproj/test'
require 'autoproj/ops/configuration'

module Autoproj
    module Ops
        describe Configuration do
            attr_reader :ops

            def mock_package_set(name, create: false, **vcs)
                vcs = VCSDefinition.from_raw(**vcs)
                raw_local_dir = File.join(make_tmpdir, 'package_set')
                flexmock(PackageSet).should_receive(:name_of).with(any, vcs).
                    and_return(name)
                flexmock(PackageSet).should_receive(:raw_local_dir_of).with(any, vcs).
                    and_return(raw_local_dir)
                if create
                    FileUtils.mkdir_p raw_local_dir
                    File.open(File.join(raw_local_dir, 'source.yml'), 'w') do |io|
                        YAML.dump(Hash['name' => name], io)
                    end
                end
                return vcs, raw_local_dir
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
                Autobuild.silent = true
            end

            describe "#sort_package_sets_by_import_order" do
                it "should handle standalone package sets that are both explicit and dependencies of other package sets gracefully (issue#30)" do
                    pkg_set0 = flexmock('set0', imports: [], explicit?: true)
                    pkg_set1 = flexmock('set1', imports: [pkg_set0], explicit?: true)
                    root_pkg_set = flexmock('root', imports: [pkg_set0, pkg_set1], explicit?: true)
                    assert_equal [pkg_set0, pkg_set1, root_pkg_set],
                        ops.sort_package_sets_by_import_order([root_pkg_set, pkg_set1, pkg_set0], root_pkg_set)
                end
            end

            describe "#load_and_update_package_sets" do
                it "applies the package set overrides using the pkg_set:repository_id keys" do
                    package_set_dir = File.join(ws.root_dir, 'package_set')
                    root_package_set = ws.manifest.main_package_set
                    root_package_set.add_raw_imported_set VCSDefinition.from_raw('type' => 'local', 'url' => '/test')
                    root_package_set.add_overrides_entry 'pkg_set:local:/test', 'url' => package_set_dir
                    FileUtils.mkdir_p package_set_dir
                    File.open(File.join(package_set_dir, 'source.yml'), 'w') do |io|
                        YAML.dump(Hash['name' => 'imported_package_set'], io)
                    end
                    ops.load_and_update_package_sets(root_package_set)
                end

                it "passes a failure to update" do
                    test_vcs, _ = mock_package_set 'test', type: 'git', url: '/test',
                        create: true
                    flexmock(ops).should_receive(:update_remote_package_set).
                        with(test_vcs, Hash).once.and_raise(e_klass = Class.new(RuntimeError))
                    root_package_set = make_root_package_set(test_vcs)

                    assert_raises(e_klass) do
                        ops.load_and_update_package_sets(root_package_set)
                    end
                end

                it "passes a failure to checkout" do
                    test_vcs, _ = mock_package_set 'test', type: 'git', url: '/test'
                    flexmock(ops).should_receive(:update_remote_package_set).
                        with(test_vcs, Hash).once.and_raise(e_klass = Class.new(RuntimeError))
                    root_package_set = make_root_package_set(test_vcs)

                    assert_raises(e_klass) do
                        ops.load_and_update_package_sets(root_package_set)
                    end
                end

                describe "ignore_errors: true" do
                    it "does pass an interrupt" do
                        test_vcs, _ = mock_package_set 'test', type: 'git', url: '/test'
                        test0_vcs, _ = mock_package_set 'test0', type: 'git', url: '/test0',
                            create: true
                        test1_vcs, _ = mock_package_set 'test1', type: 'git', url: '/test1',
                            create: true
                        flexmock(ops).should_receive(:update_remote_package_set).
                            with(test0_vcs, Hash).once.
                            and_raise(Interrupt)
                        flexmock(ops).should_receive(:update_remote_package_set).
                            with(test1_vcs, Hash).never
                        root_package_set = make_root_package_set(test0_vcs, test1_vcs)

                        assert_raises(Interrupt) do
                            ops.load_and_update_package_sets(root_package_set, ignore_errors: true)
                        end
                    end
                    it "still raises if a checkout failed" do
                        test_vcs, _ = mock_package_set 'test', type: 'git', url: '/test'
                        flexmock(ops).should_receive(:update_remote_package_set).
                            with(test_vcs, Hash).once.and_raise(e_klass = Class.new(RuntimeError))
                        root_package_set = make_root_package_set(test_vcs)

                        assert_raises(e_klass) do
                            ops.load_and_update_package_sets(root_package_set, ignore_errors: true)
                        end
                    end
                    it "collects the errors and raises an ImportFailed at the end of import" do
                        test0_vcs, _ = mock_package_set 'test0', type: 'git', url: '/test0',
                            create: true
                        test1_vcs, _ = mock_package_set 'test1', type: 'git', url: '/test1',
                            create: true
                        flexmock(ops).should_receive(:update_remote_package_set).
                            with(test0_vcs, Hash).once.
                            and_raise(error0 = Class.new(RuntimeError))
                        flexmock(ops).should_receive(:update_remote_package_set).
                            with(test1_vcs, Hash).once.
                            and_raise(error1 = Class.new(RuntimeError))
                        root_package_set = make_root_package_set(test0_vcs, test1_vcs)

                        _, e = ops.load_and_update_package_sets(root_package_set, ignore_errors: true)
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
                        @pkg_set_0 = ws_create_git_package_set 'test.pkg.set'
                        @pkg_set_1 = ws_create_git_package_set 'test.pkg.set'
                        @root_package_set = ws.manifest.main_package_set
                        root_package_set.add_raw_imported_set \
                            VCSDefinition.from_raw('type' => 'git', 'url' => pkg_set_0)
                    end

                    it "uses only the first" do
                        root_package_set.add_raw_imported_set \
                            VCSDefinition.from_raw('type' => 'git', 'url' => pkg_set_1)
                        package_sets, _ = ops.load_and_update_package_sets(root_package_set)
                        assert_equal 2, package_sets.size
                        assert_same root_package_set, package_sets.first
                        assert_equal pkg_set_0, package_sets.last.vcs.url
                    end

                    it "ensures that the user link in remotes/ points to the first match" do
                        root_package_set.add_raw_imported_set \
                            VCSDefinition.from_raw('type' => 'git', 'url' => pkg_set_1)
                        package_sets, _ = ops.load_and_update_package_sets(root_package_set)
                        assert_equal pkg_set_0, package_sets[1].vcs.url
                        assert_equal package_sets[1].raw_local_dir, File.readlink(
                            File.join(ws.config_dir, 'remotes', 'test.pkg.set'))
                    end

                    it "redirects package sets that import a colliding package set to the first" do
                        importing_pkg_set = ws_create_git_package_set 'importing.pkg.set',
                            'imports' => Array['type' => 'git', 'url' => pkg_set_1]
                        root_package_set.add_raw_imported_set \
                            VCSDefinition.from_raw('type' => 'git', 'url' => importing_pkg_set)
                        package_sets, _ = ops.load_and_update_package_sets(root_package_set)

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
                        importing_pkg_set = ws_create_git_package_set 'importing.pkg.set',
                            'imports' => Array['type' => 'git', 'url' => pkg_set_1]
                        other_importing_pkg_set = ws_create_git_package_set 'other_importing.pkg.set',
                            'imports' => Array['type' => 'git', 'url' => pkg_set_1]
                        root_package_set.add_raw_imported_set \
                            VCSDefinition.from_raw('type' => 'git', 'url' => importing_pkg_set)
                        root_package_set.add_raw_imported_set \
                            VCSDefinition.from_raw('type' => 'git', 'url' => other_importing_pkg_set)
                        package_sets, _ = ops.load_and_update_package_sets(root_package_set)

                        assert_equal 4, package_sets.size
                        assert_same  root_package_set, package_sets[0]
                        assert_equal pkg_set_0, package_sets[1].vcs.url
                        assert_equal importing_pkg_set, package_sets[2].vcs.url

                        imported  = package_sets[1]
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
                    vcs, raw_local_dir = mock_package_set('test', type: 'git', url: '/whatever')
                    flexmock(ws.os_package_installer).should_receive(:install).once.
                        with(['git'], all: nil)
                    flexmock(ops).should_receive(:update_configuration_repository).once
                    ops.update_remote_package_set(vcs, checkout_only: false)
                end

                it "does call the import if checkout_only is set but the package set is not present" do
                    vcs, raw_local_dir = mock_package_set('test', type: 'git', url: '/whatever')
                    flexmock(ops).should_receive(:update_configuration_repository).once.
                        with(vcs, 'test', raw_local_dir, Hash)
                    ops.update_remote_package_set(vcs, checkout_only: false)
                end

                it "does call the import if checkout_only is not set and the package set is present" do
                    vcs, raw_local_dir = mock_package_set('test', type: 'git', url: '/whatever')
                    FileUtils.mkdir_p(raw_local_dir)
                    flexmock(ops).should_receive(:update_configuration_repository).once
                    ops.update_remote_package_set(vcs, checkout_only: false)
                end

                it "returns right away if checkout_only is set and the remote is checked out" do
                    vcs, raw_local_dir = mock_package_set('test', type: 'git', url: '/whatever')
                    FileUtils.mkdir_p raw_local_dir
                    e = flexmock(ops).should_receive(:update_configuration_repository).never
                    ops.update_remote_package_set(vcs, checkout_only: true)
                end
            end

            describe "#update_package_sets" do
                it "has only one main package set in the resulting manifest" do
                    package_set_dir = File.join(ws.root_dir, 'package_set')
                    root_package_set = ws.manifest.main_package_set
                    root_package_set.add_raw_imported_set VCSDefinition.from_raw('type' => 'local', 'url' => package_set_dir)
                    FileUtils.mkdir_p package_set_dir
                    File.open(File.join(package_set_dir, 'source.yml'), 'w') do |io|
                        YAML.dump(Hash['name' => 'imported_package_set'], io)
                    end
                    ops.update_package_sets
                    package_sets = ws.manifest.each_package_set.to_a
                    assert_equal 2, package_sets.size
                    assert_same root_package_set, package_sets[1]
                    assert_equal VCSDefinition.from_raw('type' => 'local', 'url' => package_set_dir), package_sets[0].vcs
                end
            end

            describe "#update_configuration" do
                it "does not import the main configuration if it does not need to" do
                    flexmock(ws.manifest.vcs).should_receive(:needs_import?).
                        and_return(false)
                    flexmock(ops).should_receive(:update_main_configuration).never
                    ops.update_configuration
                end
                it "imports the main configuration if it needs it" do
                    flexmock(ws.manifest.vcs).should_receive(:needs_import?).
                        and_return(true)
                    flexmock(ops).should_receive(:update_main_configuration).once.
                        and_return([])
                    ops.update_configuration
                end
                it "passes an import failure if ignore_errors is false" do
                    flexmock(ws.manifest.vcs).should_receive(:needs_import?).
                        and_return(true)
                    flexmock(ops).should_receive(:update_configuration_repository).once.
                        and_raise(e_klass = Class.new(RuntimeError))
                    flexmock(ops).should_receive(:update_package_sets).never
                    assert_raises(e_klass) do
                        ops.update_configuration(ignore_errors: false)
                    end
                end
                it "attempts to load the configuration if ignore_errors is true" do
                    flexmock(ws.manifest.vcs).should_receive(:needs_import?).
                        and_return(true)
                    flexmock(ops).should_receive(:update_configuration_repository).once.
                        and_raise(e_klass = Class.new(RuntimeError))
                    flexmock(ops).should_receive(:update_package_sets).once.
                        and_return([])
                    assert_raises(ImportFailed) do
                        ops.update_configuration(ignore_errors: true)
                    end
                end
                it "aggregates the package set errors with the main configuration errors" do
                    flexmock(ws.manifest.vcs).should_receive(:needs_import?).
                        and_return(true)
                    flexmock(ops).should_receive(:update_configuration_repository).once.
                        and_raise(e_klass = Class.new(RuntimeError))
                    flexmock(ops).should_receive(:update_package_sets).once.
                        and_return([package_set_error = flexmock])
                    e = assert_raises(ImportFailed) do
                        ops.update_configuration(ignore_errors: true)
                    end
                    assert_equal 2, e.original_errors.size
                    assert_kind_of e_klass, e.original_errors[0]
                    assert_equal package_set_error, e.original_errors[1]
                end
            end
        end
    end
end

