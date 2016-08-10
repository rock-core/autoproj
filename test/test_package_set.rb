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

        describe "#normalize_vcs_list" do
            it "raises with a specific error message if the list is a hash" do
                e = assert_raises(InvalidYAMLFormatting) do
                    package_set.normalize_vcs_list('version_control', '/path/to/file', Hash.new)
                end
                assert_equal "wrong format for the version_control section of /path/to/file, you forgot the '-' in front of the package names", e.message
            end
            it "raises with a generic error message if the list is neither an array nor a hash" do
                e = assert_raises(InvalidYAMLFormatting) do
                    package_set.normalize_vcs_list('version_control', '/path/to/file', nil)
                end
                assert_equal "wrong format for the version_control section of /path/to/file",
                    e.message
            end

            it "converts a number to a string using convert_to_nth" do
                Hash[1 => '1st', 2 => '2nd', 3 => '3rd'].each do |n, string|
                    assert_equal string, package_set.number_to_nth(n)
                end
                assert_equal "25th", package_set.number_to_nth(25)
            end

            it "raises if the entry elements are not hashes" do
                e = assert_raises(InvalidYAMLFormatting) do
                    package_set.normalize_vcs_list('version_control', '/path/to/file', [nil])
                end
                assert_equal "wrong format for the 1st entry (nil) of the version_control section of /path/to/file, expected a package name, followed by a colon, and one importer option per following line", e.message
            end

            it "normalizes the YAML loaded if all a package keys are at the same level" do
                # - package_name:
                #   type: git
                #
                # is loaded as { 'package_name' => nil, 'type' => 'git' }
                assert_equal [['package_name', Hash['type' => 'git']]],
                    package_set.normalize_vcs_list(
                        'section', 'file', [
                            Hash['package_name' => nil, 'type' => 'git']
                        ])
            end

            it "normalizes the YAML loaded from a properly formatted source file" do
                # - package_name:
                #     type: git
                #
                # is loaded as { 'package_name' => { 'type' => 'git' } }
                assert_equal [['package_name', Hash['type' => 'git']]],
                    package_set.normalize_vcs_list(
                        'section', 'file', [
                            Hash['package_name' => Hash['type' => 'git']]
                        ])
            end

            it "accepts a package_name: none shorthand" do
                assert_equal [['package_name', Hash['type' => 'none']]],
                    package_set.normalize_vcs_list(
                        'section', 'file', [
                            Hash['package_name' => 'none']
                        ])
            end
            
            it "converts the package name into a regexp if it contains non-standard characters" do
                assert_equal [[/^test.*/, Hash['type' => 'none']]],
                    package_set.normalize_vcs_list(
                        'section', 'file', [
                            Hash['test.*' => 'none']
                        ])
            end

            it "raises InvalidYAMLFormatting for a package name without a specification" do
                e = assert_raises(InvalidYAMLFormatting) do
                    package_set.normalize_vcs_list(
                        'version_control', '/path/to/file', [Hash['test' => nil]])
                end
                assert_equal "expected 'test:' followed by version control options, but got nothing, in the 1st entry of the version_control section of /path/to/file", e.message
            end

            it "raises InvalidYAMLFormatting for an inconsistent formatted hash" do
                e = assert_raises(InvalidYAMLFormatting) do
                    package_set.normalize_vcs_list(
                        'version_control', '/path/to/file', [Hash['test' => 'with_value', 'type' => 'git']])
                end
                assert_equal "cannot make sense of the 1st entry in the version_control section of /path/to/file: {\"test\"=>\"with_value\", \"type\"=>\"git\"}", e.message
            end

            it "raises for the shorthand for any other importer than 'none'" do
                e = assert_raises(ConfigError) do
                    package_set.normalize_vcs_list(
                        'version_control', '/path/to/file', [Hash['package_name' => 'local']])
                end
                assert_equal "invalid VCS specification in the version_control section of /path/to/file: 'package_name: local'. One can only use this shorthand to declare the absence of a VCS with the 'none' keyword", e.message
            end
        end

        describe ".raw_description_file" do
            it "raises if the source.yml does not exist" do
                e = assert_raises(ConfigError) do
                    PackageSet.raw_description_file('/path/to/package_set', package_set_name: 'name_of_package_set')
                end
                assert_equal "package set name_of_package_set present in /path/to/package_set should have a source.yml file, but does not",
                    e.message
            end
            it "handles empty files gracefully" do
                dir = make_tmpdir
                FileUtils.touch(File.join(dir, 'source.yml'))
                e = assert_raises(ConfigError) do
                    PackageSet.raw_description_file(dir, package_set_name: 'name_of_package_set')
                end
                assert_equal "#{dir}/source.yml does not have a 'name' field", e.message
            end
            it "raises if the source.yml does not have a name field" do
                dir = make_tmpdir
                File.open(File.join(dir, 'source.yml'), 'w') do |io|
                    YAML.dump(Hash[], io)
                end
                e = assert_raises(ConfigError) do
                    PackageSet.raw_description_file(dir, package_set_name: 'name_of_package_set')
                end
                assert_equal "#{dir}/source.yml does not have a 'name' field", e.message
            end
        end

        describe "#inject_constants_and_config_for_expansion" do
            it "gives access to config entries that have values" do
                ws.config.set("A", "10")
                h = package_set.inject_constants_and_config_for_expansion(Hash.new)
                assert_equal "10", h['A']
            end
            it "gives access to config entries that are declared but do not have values yet" do
                ws.config.declare("A", 'string')
                flexmock(ws.config).should_receive(:get).and_return(resolved_value = flexmock)
                h = package_set.inject_constants_and_config_for_expansion(Hash.new)
                assert_equal resolved_value, h['A']
            end
            it "overrides configuration entries by manifest-level ones" do
                ws.config.set("A", '10')
                ws.manifest.add_constant_definition('A', '20')
                h = package_set.inject_constants_and_config_for_expansion(Hash.new)
                assert_equal '20', h['A']
            end
            it "overrides manifest-level entries by package-set-local ones" do
                ws.manifest.constant_definitions['A'] = '20'
                package_set.add_constant_definition('A', '30')
                h = package_set.inject_constants_and_config_for_expansion(Hash.new)
                assert_equal '30', h['A']
            end
            it "overrides package-set-local entries by ones given as argument" do
                package_set.add_constant_definition('A', '30')
                h = package_set.inject_constants_and_config_for_expansion('A' => '40')
                assert_equal '40', h['A']
            end
        end

        describe "#parse_source_definitions" do
            attr_reader :package_set
            before do
                @package_set = PackageSet.new(
                    ws, VCSDefinition.from_raw('type' => 'git', 'url' => 'https://url'),
                    raw_local_dir: '/path/to/package_set',
                    name: 'name_of_package_set')
            end

            # The expected behaviour of #parse_source_definition is to override
            # existing values with new ones if the new value is in the def, but
            # leave the value as-is otherwise. This tests this pattern.
            def assert_loads_value(attribute_name, expected_new_value, expected_current_value, source_definition: Hash[attribute_name => expected_new_value])
                current_value = package_set.send(attribute_name)
                assert_equal current_value, expected_current_value, "invalid expected current value for #{attribute_name}"

                package_set.parse_source_definition(Hash.new)
                new_value = package_set.send(attribute_name)
                assert_equal current_value, new_value, "expected #parse_source_definition called with an empty hash to not override the value of '#{attribute_name}', but it did"

                package_set.parse_source_definition(source_definition)
                new_value = package_set.send(attribute_name)
                assert_equal expected_new_value, new_value, "expected #parse_source_definition override the value of '#{attribute_name}' but it did not"
            end

            it "loads the name" do
                assert_loads_value 'name', 'new_name', 'name_of_package_set'
            end

            it "loads the required autoproj version" do
                package_set.required_autoproj_version = '2'
                assert_loads_value 'required_autoproj_version', '1', '2'
            end

            it "loads the imports" do
                original_vcs = VCSDefinition.from_raw(type: 'git', url: 'https://github.com')
                package_set.add_raw_imported_set(original_vcs, auto_imports: false)
                assert_loads_value 'imports_vcs',
                    [[VCSDefinition.from_raw('type' => 'local', 'url' => 'path/to/package'), Hash[auto_imports: false]]],
                    [[original_vcs, Hash[auto_imports: false]]],
                    source_definition: Hash['imports' => Array[Hash['type' => 'local', 'url' => 'path/to/package', 'auto_imports' => false]]]
            end

            it "loads the constant definitions" do
                package_set.add_constant_definition 'VAL', '10'
                assert_loads_value 'constants_definitions',
                    Hash['VAL' => '20'],
                    Hash['VAL' => '10'],
                    source_definition: Hash['constants' => Hash['VAL' => '20']]
            end

            it "cross-expands the constants the constant definitions" do
                package_set.parse_source_definition(
                    'constants' => Hash['A' => '10',
                                        'B' => "20$A"])
                assert_equal Hash['A' => '10', 'B' => '2010'],
                    package_set.constants_definitions
            end

            it "expands configuration variables from the workspace when expanding the constants" do
                ws.config.set('A', 10)
                package_set.parse_source_definition(
                    'constants' => Hash['B' => "20$A"])
                assert_equal Hash['B' => '2010'],
                    package_set.constants_definitions
            end

            it "normalizes the version control list" do
                source_definitions = Hash['version_control' => (version_control_list = flexmock)]
                flexmock(package_set).should_receive(:normalize_vcs_list).
                    with('version_control', package_set.source_file, version_control_list).once.
                    and_return(normalized_list = [['package_name', Hash['type' => 'test']]])
                package_set.parse_source_definition(source_definitions)
                assert_equal normalized_list, package_set.version_control
            end

            it "does not modify the version control list if there is no version_control entry in the source definition hash" do
                package_set.add_version_control_entry('package_name', Hash['type' => 'local'])
                flexmock(package_set).should_receive(:normalize_vcs_list).never
                package_set.parse_source_definition(Hash.new)
                assert_equal [['package_name', Hash['type' => 'local']]], package_set.version_control
            end

            it "resolves the default VCS entry" do
                source_definitions = Hash['version_control' => Array[Hash['default' => Hash['type' => 'local', 'url' => '/absolute/test']]]]
                package_set.parse_source_definition(source_definitions)
                default_vcs = package_set.default_importer
                assert default_vcs.local?
                assert_equal '/absolute/test', default_vcs.url
            end

            it "leaves the default VCS if the new version control field has no 'default' entry" do
                vcs = VCSDefinition.from_raw('type' => 'local', 'url' => 'test')
                package_set.default_importer = vcs
                source_definitions = Hash['version_control' => Array[]]
                package_set.parse_source_definition(source_definitions)
                assert_equal vcs, package_set.default_importer
            end

            it "normalizes the overrides list" do
                source_definitions = Hash.new
                flexmock(package_set).should_receive(:load_overrides).
                    with(Hash.new).
                    and_return([['file0', raw_list = flexmock]])
                flexmock(package_set).should_receive(:normalize_vcs_list).
                    with('overrides', 'file0', raw_list).once.
                    and_return(normalized_list = flexmock)
                package_set.parse_source_definition(Hash.new)
                assert_equal [['file0', normalized_list]], package_set.overrides
            end
            it "does not change the overrides if there is no overrides entry" do
                package_set.add_overrides_entry('package_name', VCSDefinition.none, file: 'test file')
                package_set.parse_source_definition(Hash.new)
                assert_equal [['test file', [['package_name', VCSDefinition.none]]]], package_set.overrides
            end
        end

        describe "raw_description_file" do
            it "raises InternalError if the package set's directory does not exist" do
                package_set = PackageSet.new(
                    ws, VCSDefinition.from_raw('type' => 'git', 'url' => 'https://url'),
                    raw_local_dir: '/path/to/package_set',
                    name: 'name_of_package_set')

                e = assert_raises(InternalError) do
                    package_set.raw_description_file
                end
                assert_equal "source git:https://url has not been fetched yet, cannot load description for it",
                    e.message
            end
            it "passes the package set's name to PackageSet.raw_description_file" do
                dir = make_tmpdir
                flexmock(PackageSet).should_receive(:raw_description_file).
                    with(dir, package_set_name: 'name_of_package_set').
                    once.pass_thru
                package_set = PackageSet.new(ws, VCSDefinition.from_raw('type' => 'local', 'url' => dir),
                                            name: 'name_of_package_set')
                e = assert_raises(ConfigError) do
                    package_set.raw_description_file
                end
                assert_equal "package set name_of_package_set present in #{dir} should have a source.yml file, but does not",
                    e.message
            end
        end

        describe "#version_control_field" do
            it "returns a the VCSDefinition object built from a matching entry in the list" do
                vcs, raw = package_set.version_control_field(
                    'package', [['package', Hash['type' => 'none']]])
                assert_equal [VCSDefinition::RawEntry.new(package_set, package_set.source_file, Hash['type' => 'none'])], raw
                assert_equal Hash[type: 'none'], vcs
            end
            it "uses #=== to match the entries" do
                vcs, raw = package_set.version_control_field(
                    'package', [[flexmock(:=== => true), Hash['type' => 'none']]])
                assert_equal [VCSDefinition::RawEntry.new(package_set, package_set.source_file, Hash['type' => 'none'])], raw
                assert_equal Hash[type: 'none'], vcs
            end
            it "overrides earlier entries with later matching entries" do
                vcs, raw = package_set.version_control_field(
                    'package', [
                        [flexmock(:=== => true), Hash['type' => 'git', 'url' => 'https://github.com']],
                        [flexmock(:=== => true), Hash['branch' => 'master']],
                    ])

                expected_raw = [
                    VCSDefinition::RawEntry.new(package_set, package_set.source_file, Hash['type' => 'git', 'url' => 'https://github.com']),
                    VCSDefinition::RawEntry.new(package_set, package_set.source_file, Hash['branch' => 'master'])
                ]
                assert_equal expected_raw, raw
                assert_equal Hash[type: 'git', url: 'https://github.com', branch: 'master'], vcs
            end
            it "expands variables in the VCS entries" do
                vcs, raw = package_set.version_control_field(
                    'package', [
                        [flexmock(:=== => true), Hash['type' => 'local', 'url' => '$AUTOPROJ_ROOT']]
                    ])

                assert_equal [VCSDefinition::RawEntry.new(package_set, package_set.source_file, Hash['type' => 'local', 'url' => '$AUTOPROJ_ROOT'])], raw
                assert_equal Hash[type: 'local', url: ws.root_dir], vcs
            end
            it "expands relative path URLs w.r.t. the workspace root" do
                vcs, raw = package_set.version_control_field(
                    'package', [
                        [flexmock(:=== => true), Hash['type' => 'local', 'url' => 'test']]
                    ])

                assert_equal [VCSDefinition::RawEntry.new(package_set, package_set.source_file, Hash['type' => 'local', 'url' => 'test'])], raw
                assert_equal Hash[type: 'local', url: File.join(ws.root_dir, 'test')], vcs
            end
        end
    end
end

