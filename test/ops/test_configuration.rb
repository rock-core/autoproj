require 'autoproj/test'
require 'autoproj/ops/configuration'

module Autoproj
    module Ops
        describe Configuration do
            attr_reader :ops

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
                        package_sets = ops.load_and_update_package_sets(root_package_set)
                        assert_equal 2, package_sets.size
                        assert_same root_package_set, package_sets.first
                        assert_equal pkg_set_0, package_sets.last.vcs.url
                    end

                    it "ensures that the user link in remotes/ points to the first match" do
                        root_package_set.add_raw_imported_set \
                            VCSDefinition.from_raw('type' => 'git', 'url' => pkg_set_1)
                        package_sets = ops.load_and_update_package_sets(root_package_set)
                        assert_equal pkg_set_0, package_sets[1].vcs.url
                        assert_equal package_sets[1].raw_local_dir, File.readlink(
                            File.join(ws.config_dir, 'remotes', 'test.pkg.set'))
                    end

                    it "redirects package sets that import a colliding package set to the first" do
                        importing_pkg_set = ws_create_git_package_set 'importing.pkg.set',
                            'imports' => Array['type' => 'git', 'url' => pkg_set_1]
                        root_package_set.add_raw_imported_set \
                            VCSDefinition.from_raw('type' => 'git', 'url' => importing_pkg_set)
                        package_sets = ops.load_and_update_package_sets(root_package_set)

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
                        package_sets = ops.load_and_update_package_sets(root_package_set)

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
        end
    end
end

