require 'autoproj/test'

module Autoproj
    describe OSPackageResolver do
        include Autoproj
        FOUND_PACKAGES = OSPackageResolver::FOUND_PACKAGES
        FOUND_NONEXISTENT = OSPackageResolver::FOUND_NONEXISTENT

        attr_reader :operating_system

        def setup
            super
            @operating_system = [['test', 'debian', 'default'], ['v1.0', 'v1', 'default']]
        end

        def test_it_initializes_itself_with_the_global_operating_system
            resolver = OSPackageResolver.new
            flexmock(OSPackageResolver).should_receive(:autodetect_operating_system).
                once.and_return(operating_system)
            assert_equal operating_system, resolver.operating_system
        end

        def test_supported_operating_system
            flexmock(OSPackageResolver).should_receive(:autodetect_operating_system).never
            resolver = OSPackageResolver.new
            resolver.operating_system = [['test', 'debian', 'default'], ['v1.0', 'v1', 'default']]
            assert(resolver.supported_operating_system?)
            resolver.operating_system = [['test', 'default'], ['v1.0', 'v1', 'default']]
            assert(!resolver.supported_operating_system?)
        end

        def create_osdep(data, file = nil, operating_system: self.operating_system)
            osdeps =
                if data
                    OSPackageResolver.new(
                        Hash['pkg' => data], file, operating_system: operating_system
                    )
                else
                    OSPackageResolver.new(
                        Hash.new, file, operating_system: operating_system
                    )
                end

            # Mock the package handlers
            osdeps.os_package_manager = 'apt-dpkg'
            osdeps.package_managers.clear
            osdeps.package_managers << 'apt-dpkg' << 'gem' << 'pip'
            flexmock(osdeps)
        end

        describe "#resolve_package" do
            it "handles bad formatting produced by parsing invalid YAML with old YAML Ruby versions" do
                data = { 'test' => {
                            'v1.0' => 'pkg1.0 blabla',
                            'v1.1' => 'pkg1.1 bloblo',
                            'default' => 'pkgdef'
                         }
                }
                osdeps = create_osdep(data)
                expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg1.0 blabla']]]
                assert_equal expected, osdeps.resolve_package('pkg')
            end

            it "applies aliases" do
                data = { 'test' => {
                            'v1.0' => 'pkg1.0',
                            'v1.1' => 'pkg1.1',
                            'default' => 'pkgdef'
                         }
                }
                osdeps = create_osdep(data)
                osdeps.add_aliases 'bla' => 'pkg'
                expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg1.0']]]
                assert_equal expected, osdeps.resolve_package('bla')
            end

            describe "recursive resolution" do
                attr_reader :data, :osdeps
                before do
                    @data = { 'osdep' => 'pkg1.0' }
                    @osdeps = create_osdep(data)
                end

                it "resolves the 'osdep' keyword by recursively resolving the package" do
                    flexmock(osdeps).should_receive(:resolve_package).
                        with('pkg').pass_thru
                    flexmock(osdeps).should_receive(:resolve_package).
                        with('pkg1.0').and_return([[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg1.1']]])
                    assert_equal [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg1.1']]],
                        osdeps.resolve_package('pkg')
                end

                it "raises if a recursive resolution does not match an existing package" do
                    exception = assert_raises(OSPackageResolver::InvalidRecursiveStatement) do
                        osdeps.resolve_package('pkg')
                    end
                    assert_equal "the 'pkg' osdep refers to another osdep, 'pkg1.0', which does not seem to exist: Autoproj::OSPackageResolver::InvalidRecursiveStatement",
                        exception.message
                end

                it "replaces recursive resolution by a fake package manager if resolve_recursive: is false" do
                    resolved = osdeps.resolve_package('pkg', resolve_recursive: false)
                    assert_equal [[OSPackageResolver::OSDepRecursiveResolver, OSPackageResolver::FOUND_PACKAGES, ['pkg1.0']]], resolved
                end
            end

            describe "handling of a specific OS name and version entry" do
                attr_reader :data

                before do
                    @data = { 'test' => {
                                'v1.0' => nil,
                                'v1.1' => 'pkg1.1',
                                'default' => 'pkgdef'
                             }
                    }
                end

                it "resolves a single package name" do
                    data['test']['v1.0'] = 'pkg1.0'
                    osdeps = create_osdep(data)

                    expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg1.0']]]
                    assert_equal expected, osdeps.resolve_package('pkg')
                end

                it "resolves a list of packages" do
                    data['test']['v1.0'] = ['pkg1.0', 'other_pkg']
                    osdeps = create_osdep(data)

                    expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg1.0', 'other_pkg']]]
                    assert_equal expected, osdeps.resolve_package('pkg')
                end

                it "resolves the ignore keyword" do
                    data['test']['v1.0'] = 'ignore'
                    osdeps = create_osdep(data)

                    expected = [[osdeps.os_package_manager, FOUND_PACKAGES, []]]
                    assert_equal expected, osdeps.resolve_package('pkg')
                end

                it "resolves the nonexistent keyword" do
                    data['test']['v1.0'] = 'nonexistent'
                    osdeps = create_osdep(data)

                    expected = [[osdeps.os_package_manager, FOUND_NONEXISTENT, []]]
                    assert_equal expected, osdeps.resolve_package('pkg')
                end

                it "falls back to the default entry under the OS name if the OS version does not match" do
                    data['test'].delete('v1.0')
                    osdeps = create_osdep(data)

                    expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkgdef']]]
                    assert_equal expected, osdeps.resolve_package('pkg')
                end

                it "returns an empty array if the OS matches but not the version" do
                    data['test'].delete('v1.0')
                    data['test'].delete('default')
                    osdeps = create_osdep(data)
                    assert_equal [], osdeps.resolve_package('pkg')
                end
            end

            describe "handling of a specific OS name but no version" do
                attr_reader :data

                before do
                    @data = { 'test' => nil, 'other_test' => 'pkg1.1', 'default' => 'pkgdef' }
                end

                it "resolves a single package name" do
                    data['test'] = 'pkg1.0'
                    osdeps = create_osdep(data)

                    expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg1.0']]]
                    assert_equal expected, osdeps.resolve_package('pkg')
                end

                it "resolves a list of packages" do
                    data['test'] = ['pkg1.0', 'other_pkg']
                    osdeps = create_osdep(data)

                    expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg1.0', 'other_pkg']]]
                    assert_equal expected, osdeps.resolve_package('pkg')
                end

                it "resolves the ignore keyword" do
                    data['test'] = 'ignore'
                    osdeps = create_osdep(data)

                    expected = [[osdeps.os_package_manager, FOUND_PACKAGES, []]]
                    assert_equal expected, osdeps.resolve_package('pkg')
                end

                it "resolves the nonexistent keyword" do
                    data['test'] = 'nonexistent'
                    osdeps = create_osdep(data)

                    expected = [[osdeps.os_package_manager, FOUND_NONEXISTENT, []]]
                    assert_equal expected, osdeps.resolve_package('pkg')
                end

                it "falls back to the default entry under the OS name if the OS version does not match" do
                    data.delete('test')
                    osdeps = create_osdep(data)

                    expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkgdef']]]
                    assert_equal expected, osdeps.resolve_package('pkg')
                end

                it "returns an empty array if the OS matches but not the version" do
                    data.delete('test')
                    data.delete('default')
                    osdeps = create_osdep(data)
                    assert_equal [], osdeps.resolve_package('pkg')
                end
            end
        end

        describe "handling of global entries" do
            it "adds the global entries to OS-specific ones" do
                data = [
                    'global_pkg1', 'global_pkg2',
                    { 'test' => 'pkg1.1',
                      'other_test' => 'pkg1.1',
                      'default' => 'nonexistent'
                }
                ]
                osdeps = create_osdep(data)

                expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['global_pkg1', 'global_pkg2', 'pkg1.1']]]
                assert_equal expected, osdeps.resolve_package('pkg')
            end

            it "returns the global entries even if there are no OS-specific ones" do
                data = [
                    'global_pkg1', 'global_pkg2',
                    {
                      'other_test' => 'pkg1.1',
                    }
                ]
                osdeps = create_osdep(data)

                expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['global_pkg1', 'global_pkg2']]]
                assert_equal expected, osdeps.resolve_package('pkg')
            end

            it "marks the package as nonexistent if an OS-specific version entry marks it explicitely so" do
                data = [
                    'global_pkg1', 'global_pkg2',
                    { 'test' => 'nonexistent',
                      'other_test' => 'pkg1.1'
                    }
                ]
                osdeps = create_osdep(data)

                expected = [[osdeps.os_package_manager, FOUND_NONEXISTENT, ['global_pkg1', 'global_pkg2']]]
                assert_equal expected, osdeps.resolve_package('pkg')
            end

            it "returns the global packages even if an OS-specific entry marks it as ignore" do
                data = [
                    'global_pkg1', 'global_pkg2',
                    { 'test' => 'ignore',
                      'other_test' => 'pkg1.1'
                }
                ]
                osdeps = create_osdep(data)

                expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['global_pkg1', 'global_pkg2']]]
                assert_equal expected, osdeps.resolve_package('pkg')
            end
        end

        def test_resolve_os_version_global_and_specific_packages
            data = [
                'global_pkg1', 'global_pkg2',
                { 'test' => ['pkg0', 'pkg1', { 'v1.0' => 'pkg1.0' }],
                  'other_test' => 'pkg1.1',
                  'default' => 'nonexistent'
                }
            ]
            osdeps = create_osdep(data)

            expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['global_pkg1', 'global_pkg2', 'pkg0', 'pkg1', 'pkg1.0']]]
            assert_equal expected, osdeps.resolve_package('pkg')
        end

        def test_resolve_os_version_global_and_specific_nonexistent
            data = [
                'global_pkg1', 'global_pkg2',
                { 'test' => ['pkg0', 'pkg1', { 'v1.0' => 'nonexistent' }],
                  'other_test' => 'pkg1.1',
                  'default' => 'nonexistent'
                }
            ]
            osdeps = create_osdep(data)

            expected = [[osdeps.os_package_manager, FOUND_NONEXISTENT, ['global_pkg1', 'global_pkg2', 'pkg0', 'pkg1']]]
            assert_equal expected, osdeps.resolve_package('pkg')
        end

        def test_resolve_os_version_global_and_specific_ignore
            data = [
                'global_pkg1', 'global_pkg2',
                { 'test' => ['pkg0', 'pkg1', { 'v1.0' => 'ignore' }],
                  'other_test' => 'pkg1.1',
                  'default' => 'nonexistent'
                }
            ]
            osdeps = create_osdep(data)

            expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['global_pkg1', 'global_pkg2', 'pkg0', 'pkg1']]]
            assert_equal expected, osdeps.resolve_package('pkg')
        end

        def test_resolve_os_version_global_and_specific_does_not_exist
            data = [
                'global_pkg1', 'global_pkg2',
                { 'test' => ['pkg0', 'pkg1', { 'v1.1' => 'pkg1.1' }],
                  'other_test' => 'pkg1.1',
                  'default' => 'nonexistent'
                }
            ]
            osdeps = create_osdep(data)

            expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['global_pkg1', 'global_pkg2', 'pkg0', 'pkg1']]]
            assert_equal expected, osdeps.resolve_package('pkg')
        end

        def test_resolve_osindep_packages_global
            data = 'gem'
            osdeps = create_osdep(data)
            expected = [['gem', FOUND_PACKAGES, ['pkg']]]
            assert_equal expected, osdeps.resolve_package('pkg')

            data = { 'gem' => 'gempkg' }
            osdeps = create_osdep(data)
            expected = [['gem', FOUND_PACKAGES, ['gempkg']]]
            assert_equal expected, osdeps.resolve_package('pkg')

            data = { 'gem' => ['gempkg', 'gempkg1'] }
            osdeps = create_osdep(data)
            expected = [['gem', FOUND_PACKAGES, ['gempkg', 'gempkg1']]]
            assert_equal expected, osdeps.resolve_package('pkg')

            data = 'pip'
            osdeps = create_osdep(data)
            expected = [['pip', FOUND_PACKAGES, ['pkg']]]
            assert_equal expected, osdeps.resolve_package('pkg')
        end

        def test_resolve_osindep_packages_specific
            data = ['gem', { 'test' => { 'gem' => 'gempkg' } } ]
            osdeps = create_osdep(data)
            expected = [['gem', FOUND_PACKAGES, ['pkg', 'gempkg']]]
            assert_equal expected, osdeps.resolve_package('pkg')
        end

        def test_specific_os_version_supersedes_nonspecific_one
            data = { 'debian' => 'binary_package', 'test' => { 'gem' => 'gempkg' } }
            osdeps = create_osdep(data)
            expected = [['gem', FOUND_PACKAGES, ['gempkg']]]
            assert_equal expected, osdeps.resolve_package('pkg')

            data = { 'default' => { 'gem' => 'gem_package' }, 'test' => 'binary_package' }
            osdeps = create_osdep(data)
            expected = [[osdeps.os_package_manager, FOUND_PACKAGES, ['binary_package']]]
            assert_equal expected, osdeps.resolve_package('pkg')
        end

        def test_resolve_mixed_os_and_osindep_dependencies
            data = { 'test' => { 'default' => 'ospkg', 'gem' => 'gempkg' } }

            osdeps = create_osdep(data)
            expected = [
                [osdeps.os_package_manager, FOUND_PACKAGES, ['ospkg']],
                ['gem', FOUND_PACKAGES, ['gempkg']]
            ].to_set
            assert_equal expected, osdeps.resolve_package('pkg').to_set
        end

        def test_availability_of
            osdeps = flexmock(OSPackageResolver.new)
            osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
                [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg1']],
                 ['gem', FOUND_PACKAGES, ['gempkg1']]])
            assert_equal OSPackageResolver::AVAILABLE, osdeps.availability_of('pkg0')

            osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
                [[osdeps.os_package_manager, FOUND_PACKAGES, []],
                 ['gem', FOUND_PACKAGES, ['gempkg1']]])
            assert_equal OSPackageResolver::AVAILABLE, osdeps.availability_of('pkg0')

            osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
                [[osdeps.os_package_manager, FOUND_PACKAGES, []],
                 ['gem', FOUND_PACKAGES, []]])
            assert_equal OSPackageResolver::IGNORE, osdeps.availability_of('pkg0')

            osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
                [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg1']],
                 ['gem', FOUND_NONEXISTENT, []]])
            assert_equal OSPackageResolver::NONEXISTENT, osdeps.availability_of('pkg0')

            osdeps.should_receive(:resolve_package).with('pkg0').once.and_return([])
            assert_equal OSPackageResolver::WRONG_OS, osdeps.availability_of('pkg0')

            osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(nil)
            assert_equal OSPackageResolver::NO_PACKAGE, osdeps.availability_of('pkg0')
        end

        def test_has_p
            osdeps = flexmock(OSPackageResolver.new)
            osdeps.should_receive(:availability_of).with('pkg0').once.
                and_return(OSPackageResolver::AVAILABLE)
            assert(osdeps.has?('pkg0'))

            osdeps.should_receive(:availability_of).with('pkg0').once.
                and_return(OSPackageResolver::IGNORE)
            assert(osdeps.has?('pkg0'))

            osdeps.should_receive(:availability_of).with('pkg0').once.
                and_return(OSPackageResolver::UNKNOWN_OS)
            assert(!osdeps.has?('pkg0'))

            osdeps.should_receive(:availability_of).with('pkg0').once.
                and_return(OSPackageResolver::WRONG_OS)
            assert(!osdeps.has?('pkg0'))

            osdeps.should_receive(:availability_of).with('pkg0').once.
                and_return(OSPackageResolver::NONEXISTENT)
            assert(!osdeps.has?('pkg0'))

            osdeps.should_receive(:availability_of).with('pkg0').once.
                and_return(OSPackageResolver::NO_PACKAGE)
            assert(!osdeps.has?('pkg0'))
        end

        def test_resolve_os_packages
            osdeps = flexmock(OSPackageResolver.new)
            osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
                [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg0']]])
            osdeps.should_receive(:resolve_package).with('pkg1').once.and_return(
                [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg1']],
                 ['gem', FOUND_PACKAGES, ['gempkg1']]])
            osdeps.should_receive(:resolve_package).with('pkg2').once.and_return(
                [['gem', FOUND_PACKAGES, ['gempkg2']]])
            expected =
                [[osdeps.os_package_manager, ['pkg0', 'pkg1']],
                 ['gem', ['gempkg1', 'gempkg2']]]
            assert_equal expected, osdeps.resolve_os_packages(['pkg0', 'pkg1', 'pkg2'])

            osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
                [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg0']]])
            osdeps.should_receive(:resolve_package).with('pkg1').once.and_return(
                [[osdeps.os_package_manager, FOUND_PACKAGES, []]])
            osdeps.should_receive(:resolve_package).with('pkg2').once.and_return(
                [['gem', FOUND_PACKAGES, ['gempkg2']]])
            expected =
                [[osdeps.os_package_manager, ['pkg0']],
                 ['gem', ['gempkg2']]]
            assert_equal expected, osdeps.resolve_os_packages(['pkg0', 'pkg1', 'pkg2'])

            osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(nil)
            osdeps.should_receive(:resolve_package).with('pkg1').never
            osdeps.should_receive(:resolve_package).with('pkg2').never
            assert_raises(MissingOSDep) { osdeps.resolve_os_packages(['pkg0', 'pkg1', 'pkg2']) }

            osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
                [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg0']]])
            osdeps.should_receive(:resolve_package).with('pkg1').once.and_return(
                [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg1']],
                 ['gem', FOUND_PACKAGES, ['gempkg1']]])
            osdeps.should_receive(:resolve_package).with('pkg2').once.and_return(nil)
            expected =
                [[osdeps.os_package_manager, ['pkg0']],
                 ['gem', ['gempkg1', 'gempkg2']]]
            assert_raises(MissingOSDep) { osdeps.resolve_os_packages(['pkg0', 'pkg1', 'pkg2']) }

            osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
                [[osdeps.os_package_manager, FOUND_NONEXISTENT, ['pkg0']]])
            osdeps.should_receive(:resolve_package).with('pkg1').never
            osdeps.should_receive(:resolve_package).with('pkg2').never
            assert_raises(MissingOSDep) { osdeps.resolve_os_packages(['pkg0', 'pkg1', 'pkg2']) }

            osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
                [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg0']]])
            osdeps.should_receive(:resolve_package).with('pkg1').once.and_return(
                [[osdeps.os_package_manager, FOUND_PACKAGES, ['pkg1']],
                 ['gem', FOUND_NONEXISTENT, ['gempkg1']]])
            osdeps.should_receive(:resolve_package).with('pkg2').never
            assert_raises(MissingOSDep) { osdeps.resolve_os_packages(['pkg0', 'pkg1', 'pkg2']) }
        end

        def test_resolve_os_packages_unsupported_os_non_existent_dependency
            osdeps = create_osdep(nil)
            flexmock(osdeps).should_receive(:supported_operating_system?).and_return(false)
            assert_raises(MissingOSDep) { osdeps.resolve_os_packages(['a_package']) }
        end

        def test_resolve_package_availability_unsupported_os_non_existent_dependency
            osdeps = create_osdep(nil)
            flexmock(osdeps).should_receive(:supported_operating_system?).and_return(false)
            assert_equal OSPackageResolver::NO_PACKAGE, osdeps.availability_of('a_package')
        end

        def test_resolve_package_availability_unsupported_os_existent_dependency
            osdeps = create_osdep({ 'an_os' => 'bla' })
            flexmock(osdeps).should_receive(:supported_operating_system?).and_return(false)
            assert_equal OSPackageResolver::WRONG_OS, osdeps.availability_of('pkg')
        end

        DATA_DIR = File.expand_path('data', File.dirname(__FILE__))
        def test_os_from_os_release_returns_nil_if_the_os_release_file_is_not_found
            assert !OSPackageResolver.os_from_os_release('does_not_exist')
        end
        def test_os_from_os_release_handles_quoted_and_unquoted_fields
            names, versions = OSPackageResolver.os_from_os_release(
                File.join(DATA_DIR, 'os_release.with_missing_optional_fields'))
            assert_equal ['name'], names
            assert_equal ['version_id'], versions
        end
        def test_os_from_os_release_handles_optional_fields
            names, versions = OSPackageResolver.os_from_os_release(
                File.join(DATA_DIR, 'os_release.with_missing_optional_fields'))
            assert_equal ['name'], names
            assert_equal ['version_id'], versions
        end
        def test_os_from_os_release_parses_the_version_field
            _, versions = OSPackageResolver.os_from_os_release(
                File.join(DATA_DIR, 'os_release.with_complex_version_field'))
            assert_equal ['version_id', 'version', 'codename', 'codename_bis'], versions
        end
        def test_os_from_os_release_removes_duplicate_values
            names, versions = OSPackageResolver.os_from_os_release(
                File.join(DATA_DIR, 'os_release.with_duplicate_values'))
            assert_equal ['id'], names
            assert_equal ['version_id', 'codename'], versions
        end
        def test_os_from_lsb_returns_nil_if_lsb_release_is_not_found_in_path
            flexmock(Autobuild).should_receive(:find_in_path).with('lsb_release').and_return(nil)
            assert !OSPackageResolver.os_from_lsb
        end

        describe "#merge" do
            def capture_warn
                messages = Array.new
                FlexMock.use(Autoproj) do |mock|
                    mock.should_receive(:warn).and_return do |message|
                        messages << message
                    end
                    yield
                end
                messages
            end

            it "updates an existing entry" do
                osdeps0 = create_osdep(Hash['test' => ['osdep0'], 'gem' => ['gem0']], 'bla/bla')
                osdeps1 = create_osdep(Hash['test' => ['osdep1'], 'gem' => ['gem1']], 'bla/blo')
                capture_warn { osdeps0.merge(osdeps1) }
                assert_equal [["apt-dpkg", 0, ["osdep1"]], ["gem", 0, ["gem1"]]],
                    osdeps0.resolve_package('pkg')
            end

            it "issues a warning if two definitions differ only by the operating system packages" do
                osdeps0 = create_osdep(Hash['test' => ['osdep0'], 'gem' => ['gem0']], 'bla/bla')
                osdeps1 = create_osdep(Hash['test' => ['osdep1'], 'gem' => ['gem0']], 'bla/blo')
                messages = capture_warn { osdeps0.merge(osdeps1) }
                assert_equal <<-EOD.chomp, messages.join("\n")
osdeps definition for pkg, previously defined in bla/bla overridden by bla/blo:
  resp. apt-dpkg: osdep0
        gem: gem0
  and   apt-dpkg: osdep1
        gem: gem0
                EOD
            end

            it "issues a warning if two definitions differ only by an os independent package" do
                osdeps0 = create_osdep(Hash['test' => ['osdep0'], 'gem' => ['gem0']], 'bla/bla')
                osdeps1 = create_osdep(Hash['test' => ['osdep0'], 'gem' => ['gem1']], 'bla/blo')
                messages = capture_warn { osdeps0.merge(osdeps1) }
                assert_equal <<-EOD.chomp, messages.join("\n")
osdeps definition for pkg, previously defined in bla/bla overridden by bla/blo:
  resp. apt-dpkg: osdep0
        gem: gem0
  and   apt-dpkg: osdep0
        gem: gem1
                EOD
            end

            it "does not issue a warning if two definitions differ only by an os independent package" do
                osdeps0 = create_osdep(Hash['test' => ['osdep0'], 'gem' => ['gem0'], 'os1' => ['osdep0']], 'bla/bla')
                osdeps1 = create_osdep(Hash['test' => ['osdep0'], 'gem' => ['gem0'], 'os1' => ['osdep1']], 'bla/blo')
                messages = capture_warn { osdeps0.merge(osdeps1) }
                assert messages.empty?
            end

            it "does not resolve entries recursively" do
                osdeps0 = create_osdep(Hash['osdep' => ['osdep0']], 'bla/bla')
                osdeps1 = create_osdep(Hash['osdep' => ['osdep1']], 'bla/blo')
                messages = capture_warn { osdeps0.merge(osdeps1) }
                assert_equal <<-EOD.chomp, messages.join("\n")
osdeps definition for pkg, previously defined in bla/bla overridden by bla/blo:
  resp. osdep: osdep0
  and   osdep: osdep1
                EOD
            end
        end

        describe "prefer_indep_over_os_packages is set" do
            def create_osdep(*)
                resolver = super
                resolver.prefer_indep_over_os_packages = true
                resolver
            end

            it "resolves the default entry first" do
                resolver = create_osdep(Hash['test' => ['osdep0'], 'default' => 'gem'], 'bla/bla')
                assert_equal [['gem', ['pkg']]], resolver.resolve_os_packages(['pkg'])
            end
            it "resolves the default entry first" do
                resolver = create_osdep(Hash['test' => ['osdep0'], 'default' => Hash['gem' => 'gem0']], 'bla/bla')
                assert_equal [['gem', ['gem0']]], resolver.resolve_os_packages(['pkg'])
            end
            it "falls back to the OS-specific entry if there is no default entry" do
                resolver = create_osdep(Hash['test' => ['osdep0']], 'bla/bla')
                assert_equal [['apt-dpkg', ['osdep0']]], resolver.resolve_os_packages(['pkg'])
            end
            it "does not affect os versions, only os names" do
                resolver = create_osdep(Hash['test' => Hash['v1.0' => 'osdep0', 'default' => 'gem']], 'bla/bla')
                assert_equal [['apt-dpkg', ['osdep0']]], resolver.resolve_os_packages(['pkg'])
            end
        end

        describe "#os_package_manager=" do
            attr_reader :resolver
            before do
                @resolver = OSPackageResolver.new(
                    operating_system: [['test'], []],
                    package_managers: ['os1', 'os2'],
                    os_package_manager: 'os1')
            end

            it "sets the package manager" do
                resolver.os_package_manager = 'os2'
                assert_equal 'os2', resolver.os_package_manager
            end
            it "raises if the given name does not match a declared package manager" do
                ws_create
                # NOTE: we pick an existing package manager ON PURPOSE. The
                # resolver-under-test has a different list, so this tests that
                # the validation does not resolve against the global list
                assert_raises(ArgumentError) do
                    resolver.os_package_manager = 'apt-dpkg'
                end
            end
        end

        describe "#known_operating_system?" do
            attr_reader :resolver
            before do
                @resolver = ws_create_os_package_resolver
                flexmock(resolver)
            end
            it "returns true if operating_system is not empty" do
                assert resolver.known_operating_system?
            end
            it "returns false if the operating_system is empty" do
                resolver.should_receive(:operating_system).
                    and_return([[], []])
                refute resolver.known_operating_system?
            end
        end

        describe "#availability_of" do
            attr_reader :resolver
            before do
                @resolver = ws_create_os_package_resolver
                flexmock(resolver)
            end
            it "returns WRONG_OS if the OS is known but the package was resolved to empty" do
                resolver.should_receive(:resolve_package).with(name = flexmock).
                    and_return([])
                assert_equal OSPackageResolver::WRONG_OS, resolver.availability_of(name)
            end
            it "returns UNKNOWN_OS if the OS is unknown and the package was resolved to empty" do
                resolver.operating_system = [[], []]
                resolver.should_receive(:resolve_package).with(name = flexmock).
                    and_return([])
                assert_equal OSPackageResolver::UNKNOWN_OS, resolver.availability_of(name)
            end
        end
    end
end

