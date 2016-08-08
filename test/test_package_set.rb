require 'autoproj/test'

module Autoproj
    describe PackageSet do
        attr_reader :package_set, :raw_local_dir, :vcs
        before do
            ws_create
            @vcs = VCSDefinition.from_raw(type: 'local', url: '/path/to/set')
            @raw_local_dir = File.join(ws.root_dir, 'package_set')
            @package_set = PackageSet.new(
                ws, vcs, raw_local_dir: raw_local_dir)
        end

        it "is not a main package set" do
            refute package_set.main?
        end

        it "is local if its vcs is" do
            assert package_set.local?
            flexmock(package_set.vcs).should_receive(:local?).and_return(false)
            refute package_set.local?
        end

        it "is empty on construction" do
            assert package_set.empty?
        end

        describe ".name_of" do
            it "returns the package set name as present on disk if it is present" do
                FileUtils.mkdir_p File.join(ws.root_dir, 'package_set')
                File.open(File.join(package_set.raw_local_dir, 'source.yml'), 'w') do |io|
                    io.write YAML.dump(Hash['name' => 'test'])
                end
                assert_equal 'test', PackageSet.name_of(ws, vcs, raw_local_dir: raw_local_dir)
            end
            it "uses the VCS as name if the package set is not present" do
                assert_equal 'local:/path/to/set', PackageSet.name_of(ws, vcs, raw_local_dir: raw_local_dir)
            end
        end

        describe ".raw_local_dir_of" do
            it "returns the local path if the VCS is local" do
                assert_equal '/path/to/package_set', PackageSet.raw_local_dir_of(ws,
                    VCSDefinition.from_raw('type' => 'local', 'url' => '/path/to/package_set'))
            end
            it "returns a normalized subdirectory of the workspace's remotes dir the VCS is remote" do
                vcs = VCSDefinition.from_raw(
                    'type' => 'git',
                    'url' => 'https://github.com/test/url',
                    'branch' => 'test_branch')
                repository_id = Autobuild.git(
                    'https://github.com/test/url',
                    branch: 'test_branch').repository_id
                path = PackageSet.raw_local_dir_of(ws, vcs)
                assert path.start_with?(ws.remotes_dir)
                assert_equal repository_id.gsub(/[^\w]/, '_'),
                    path[(ws.remotes_dir.size + 1)..-1]
            end
        end

        describe "initialize" do
            it "propagates the workspace's resolver setup" do
                resolver = package_set.os_package_resolver
                # Values are from Autoproj::Test#ws_create_os_package_resolver
                assert_equal [['test_os_family'], ['test_os_version']],
                    resolver.operating_system
                assert_equal 'os', resolver.os_package_manager
                assert_equal ws_package_managers.keys, resolver.package_managers
            end
        end
        describe "#present?" do
            it "returns false if the local dir does not exist" do
                refute package_set.present?
            end
            it "returns true if the local dir exists" do
                FileUtils.mkdir_p File.join(ws.root_dir, 'package_set')
                assert package_set.present?
            end
        end

        describe "#resolve_definition" do
            it "resolves a local package set relative to the config dir" do
                FileUtils.mkdir_p(dir = File.join(ws.config_dir, 'dir'))
                vcs, options = PackageSet.resolve_definition(ws, 'dir')
                assert_equal Hash[auto_imports: true], options
                assert vcs.local?
                assert_equal dir, vcs.url
            end
            it "resolves a local package set given in absolute" do
                FileUtils.mkdir_p(dir = File.join(ws.config_dir, 'dir'))
                vcs, options = PackageSet.resolve_definition(ws, dir)
                assert_equal Hash[auto_imports: true], options
                assert vcs.local?
                assert_equal dir, vcs.url
            end
            it "raises if given a relative path that does not exist" do
                e = assert_raises(ArgumentError) do
                    PackageSet.resolve_definition(ws, 'dir')
                end
                assert_equal "'dir' is neither a remote source specification, nor an existing local directory",
                    e.message
            end
            it "raises if given a full path that does not exist" do
                e = assert_raises(ArgumentError) do
                    PackageSet.resolve_definition(ws, '/full/dir')
                end
                assert_equal "'/full/dir' is neither a remote source specification, nor an existing local directory",
                    e.message
            end
        end
        
        describe "#repository_id" do
            it "returns the package set path if the set is local" do
                package_set = PackageSet.new(ws, VCSDefinition.from_raw('type' => 'local', 'url' => '/path/to/set'))
                assert_equal '/path/to/set', package_set.repository_id
            end
            it "returns the importer's repository_id if there is one" do
                vcs = VCSDefinition.from_raw(
                    'type' => 'git',
                    'url' => 'https://github.com/test/url',
                    'branch' => 'test_branch')
                repository_id = Autobuild.git(
                    'https://github.com/test/url',
                    branch: 'test_branch').repository_id

                package_set = PackageSet.new(ws, vcs)
                assert_equal repository_id, package_set.repository_id
            end

            it "returns the vcs as string if the importer has no repository_id" do
                vcs = VCSDefinition.from_raw(
                    'type' => 'git',
                    'url' => 'https://github.com/test/url',
                    'branch' => 'test_branch')
                importer = vcs.create_autobuild_importer
                flexmock(importer).should_receive(:respond_to?).with(:repository_id).and_return(false)
                flexmock(vcs).should_receive(:create_autobuild_importer).and_return(importer)
                package_set = PackageSet.new(ws, vcs, raw_local_dir: '/path/to/set')
                assert_equal vcs.to_s, package_set.repository_id
            end
        end
    end
end

