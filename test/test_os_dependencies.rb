$LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))
$LOAD_PATH.unshift File.expand_path('../', File.dirname(__FILE__))
require 'test/unit'
require 'autoproj'
require 'flexmock/test_unit'

require 'test/package_managers/test_gem'

class TC_OSDependencies < Test::Unit::TestCase
    include Autoproj
    FOUND_PACKAGES = Autoproj::OSDependencies::FOUND_PACKAGES
    FOUND_NONEXISTENT = Autoproj::OSDependencies::FOUND_NONEXISTENT

    def setup
        Autoproj::OSDependencies.operating_system = [['test', 'debian', 'default'], ['v1.0', 'v1', 'default']]
    end

    def test_supported_operating_system
        Autoproj::OSDependencies.operating_system = [['test', 'debian', 'default'], ['v1.0', 'v1', 'default']]
        assert(Autoproj::OSDependencies.supported_operating_system?)
        Autoproj::OSDependencies.operating_system = [['test', 'default'], ['v1.0', 'v1', 'default']]
        assert(!Autoproj::OSDependencies.supported_operating_system?)
    end

    def create_osdep(data)
        osdeps = OSDependencies.new(data)
        # Mock the package handlers
        osdeps.os_package_handler = flexmock(PackageManagers::Manager.new(['apt-dpkg']))
        osdeps.package_handlers.clear
        osdeps.package_handlers['apt-dpkg'] = osdeps.os_package_handler
        osdeps.package_handlers['gem'] = flexmock(PackageManagers::Manager.new(['gem']))
        osdeps.package_handlers['pip'] = flexmock(PackageManagers::Manager.new(['pip']))
        flexmock(osdeps)
    end

    def test_resolve_package_calls_specific_formatting
        data = { 'pkg' => {
                'test' => {
                    'v1.0' => 'pkg1.0 blabla',
                    'v1.1' => 'pkg1.1 bloblo',
                    'default' => 'pkgdef'
                 }
        } }
        osdeps = create_osdep(data)
        osdeps.os_package_handler.should_receive(:parse_package_entry).
            and_return { |arg| arg.split(" ") }.once

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, [['pkg1.0', 'blabla']]]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_package_applies_aliases
        data = { 'pkg' => {
                'test' => {
                    'v1.0' => 'pkg1.0',
                    'v1.1' => 'pkg1.1',
                    'default' => 'pkgdef'
                 }
        } }
        Autoproj::OSDependencies.alias('pkg', 'bla')
        osdeps = create_osdep(data)
        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkg1.0']]]
        assert_equal expected, osdeps.resolve_package('bla')
    end

    def test_resolve_specific_os_name_and_version_single_package
        data = { 'pkg' => {
                'test' => {
                    'v1.0' => 'pkg1.0',
                    'v1.1' => 'pkg1.1',
                    'default' => 'pkgdef'
                 }
        } }
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkg1.0']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_specific_os_name_and_version_package_list
        data = { 'pkg' => {
                'test' => {
                    'v1.0' => ['pkg1.0', 'other_pkg'],
                    'v1.1' => 'pkg1.1',
                    'default' => 'pkgdef'
                 }
        } }
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkg1.0', 'other_pkg']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_specific_os_name_and_version_ignore
        data = { 'pkg' => {
                'test' => {
                    'v1.0' => 'ignore',
                    'v1.1' => 'pkg1.1',
                    'default' => 'pkgdef'
                 }
        } }
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, []]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_specific_os_name_and_version_fallback
        data = { 'pkg' =>
                 { 'test' => 
                   { 'v1.1' => 'pkg1.1',
                     'default' => 'pkgdef'
                   }
                 }        
               }
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkgdef']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_specific_os_name_and_version_nonexistent
        data = { 'pkg' => {
                'test' => {
                    'v1.0' => 'nonexistent',
                    'v1.1' => 'pkg1.1',
                    'default' => 'pkgdef'
                 }
        } }
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_NONEXISTENT, []]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_specific_os_name_and_version_not_found
        data = { 'pkg' => {
                'test' => { 'v1.1' => 'pkg1.1', }
        } }
        osdeps = create_osdep(data)
        assert_equal [], osdeps.resolve_package('pkg')
    end

    def test_resolve_specific_os_name_single_package
        data = { 'pkg' => { 'test' => 'pkg1.0', 'other_test' => 'pkg1.1', 'default' => 'pkgdef' } }
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkg1.0']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_specific_os_name_package_list
        data = { 'pkg' => { 'test' => ['pkg1.0', 'other_pkg'], 'other_test' => 'pkg1.1', 'default' => 'pkgdef' } }
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkg1.0', 'other_pkg']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_specific_os_name_ignore
        data = { 'pkg' => { 'test' => 'ignore', 'other_test' => 'pkg1.1', 'default' => 'pkgdef' } }
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, []]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_specific_os_name_fallback
        data = { 'pkg' => { 'other_test' => 'pkg1.1', 'default' => 'pkgdef' } }
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkgdef']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_specific_os_name_and_version_nonexistent
        data = { 'pkg' => { 'test' => 'nonexistent', 'other_test' => 'pkg1.1' } }
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_NONEXISTENT, []]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_specific_os_name_and_version_not_found
        data = { 'pkg' => { 'other_test' => 'pkg1.1' } }
        osdeps = create_osdep(data)

        assert_equal [], osdeps.resolve_package('pkg')
    end

    def test_resolve_os_name_global_and_specific_packages
        data = { 'pkg' => [
            'global_pkg1', 'global_pkg2',
            { 'test' => 'pkg1.1',
              'other_test' => 'pkg1.1',
              'default' => 'nonexistent'
            }
        ]}
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, ['global_pkg1', 'global_pkg2', 'pkg1.1']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_os_name_global_and_specific_does_not_exist
        data = { 'pkg' => [
            'global_pkg1', 'global_pkg2',
            {
              'other_test' => 'pkg1.1',
            }
        ]}
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, ['global_pkg1', 'global_pkg2']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_os_name_global_and_nonexistent
        data = { 'pkg' => [
            'global_pkg1', 'global_pkg2',
            { 'test' => 'nonexistent',
              'other_test' => 'pkg1.1'
            }
        ]}
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_NONEXISTENT, ['global_pkg1', 'global_pkg2']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_os_name_global_and_ignore
        data = { 'pkg' => [
            'global_pkg1', 'global_pkg2',
            { 'test' => 'ignore',
              'other_test' => 'pkg1.1'
            }
        ]}
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, ['global_pkg1', 'global_pkg2']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_os_version_global_and_specific_packages
        data = { 'pkg' => [
            'global_pkg1', 'global_pkg2',
            { 'test' => ['pkg0', 'pkg1', { 'v1.0' => 'pkg1.0' }],
              'other_test' => 'pkg1.1',
              'default' => 'nonexistent'
            }
        ]}
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, ['global_pkg1', 'global_pkg2', 'pkg0', 'pkg1', 'pkg1.0']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_os_version_global_and_specific_nonexistent
        data = { 'pkg' => [
            'global_pkg1', 'global_pkg2',
            { 'test' => ['pkg0', 'pkg1', { 'v1.0' => 'nonexistent' }],
              'other_test' => 'pkg1.1',
              'default' => 'nonexistent'
            }
        ]}
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_NONEXISTENT, ['global_pkg1', 'global_pkg2', 'pkg0', 'pkg1']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_os_version_global_and_specific_ignore
        data = { 'pkg' => [
            'global_pkg1', 'global_pkg2',
            { 'test' => ['pkg0', 'pkg1', { 'v1.0' => 'ignore' }],
              'other_test' => 'pkg1.1',
              'default' => 'nonexistent'
            }
        ]}
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, ['global_pkg1', 'global_pkg2', 'pkg0', 'pkg1']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_os_version_global_and_specific_does_not_exist
        data = { 'pkg' => [
            'global_pkg1', 'global_pkg2',
            { 'test' => ['pkg0', 'pkg1', { 'v1.1' => 'pkg1.1' }],
              'other_test' => 'pkg1.1',
              'default' => 'nonexistent'
            }
        ]}
        osdeps = create_osdep(data)

        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, ['global_pkg1', 'global_pkg2', 'pkg0', 'pkg1']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_osindep_packages_global
        data = { 'pkg' => 'gem' }
        osdeps = create_osdep(data)
        expected = [[osdeps.package_handlers['gem'], FOUND_PACKAGES, ['pkg']]]
        assert_equal expected, osdeps.resolve_package('pkg')

        data = { 'pkg' => { 'gem' => 'gempkg' }}
        osdeps = create_osdep(data)
        expected = [[osdeps.package_handlers['gem'], FOUND_PACKAGES, ['gempkg']]]
        assert_equal expected, osdeps.resolve_package('pkg')

        data = { 'pkg' => { 'gem' => ['gempkg', 'gempkg1'] }}
        osdeps = create_osdep(data)
        expected = [[osdeps.package_handlers['gem'], FOUND_PACKAGES, ['gempkg', 'gempkg1']]]
        assert_equal expected, osdeps.resolve_package('pkg')

        data = { 'pkg' => 'pip' }
        osdeps = create_osdep(data)
        expected = [[osdeps.package_handlers['pip'], FOUND_PACKAGES, ['pkg']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_osindep_packages_specific
        data = { 'pkg' => ['gem', { 'test' => { 'gem' => 'gempkg' } } ] }
        osdeps = create_osdep(data)
        expected = [[osdeps.package_handlers['gem'], FOUND_PACKAGES, ['pkg', 'gempkg']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_specific_os_version_supersedes_nonspecific_one
        data = { 'pkg' =>
                 {
                   'debian' => 'binary_package',
                   'test' => { 'gem' => 'gempkg' }
                 }
               }
        osdeps = create_osdep(data)
        expected = [[osdeps.package_handlers['gem'], FOUND_PACKAGES, ['gempkg']]]
        assert_equal expected, osdeps.resolve_package('pkg')

        data = { 'pkg' =>
                 {
                   'default' => { 'gem' => 'gem_package' },
                   'test' => 'binary_package'
                 }
               }
        osdeps = create_osdep(data)
        expected = [[osdeps.os_package_handler, FOUND_PACKAGES, ['binary_package']]]
        assert_equal expected, osdeps.resolve_package('pkg')
    end

    def test_resolve_mixed_os_and_osindep_dependencies
        data = { 'pkg' =>
                 { 'test' => { 'default' => 'ospkg', 'gem' => 'gempkg' }
                 }
               }

        osdeps = create_osdep(data)
        expected = [
            [osdeps.os_package_handler, FOUND_PACKAGES, ['ospkg']],
            [osdeps.package_handlers['gem'], FOUND_PACKAGES, ['gempkg']]
        ].to_set
        assert_equal expected, osdeps.resolve_package('pkg').to_set
    end

    def test_availability_of
        osdeps = flexmock(OSDependencies.new)
        osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
            [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkg1']],
             [osdeps.package_handlers['gem'], FOUND_PACKAGES, ['gempkg1']]])
        assert_equal OSDependencies::AVAILABLE, osdeps.availability_of('pkg0')

        osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
            [[osdeps.os_package_handler, FOUND_PACKAGES, []],
             [osdeps.package_handlers['gem'], FOUND_PACKAGES, ['gempkg1']]])
        assert_equal OSDependencies::AVAILABLE, osdeps.availability_of('pkg0')

        osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
            [[osdeps.os_package_handler, FOUND_PACKAGES, []],
             [osdeps.package_handlers['gem'], FOUND_PACKAGES, []]])
        assert_equal OSDependencies::IGNORE, osdeps.availability_of('pkg0')

        osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
            [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkg1']],
             [osdeps.package_handlers['gem'], FOUND_NONEXISTENT, []]])
        assert_equal OSDependencies::NONEXISTENT, osdeps.availability_of('pkg0')

        osdeps.should_receive(:resolve_package).with('pkg0').once.and_return([])
        assert_equal OSDependencies::WRONG_OS, osdeps.availability_of('pkg0')

        osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(nil)
        assert_equal OSDependencies::NO_PACKAGE, osdeps.availability_of('pkg0')
    end

    def test_has_p
        osdeps = flexmock(OSDependencies.new)
        osdeps.should_receive(:availability_of).with('pkg0').once.
            and_return(OSDependencies::AVAILABLE)
        assert(osdeps.has?('pkg0'))

        osdeps.should_receive(:availability_of).with('pkg0').once.
            and_return(OSDependencies::IGNORE)
        assert(osdeps.has?('pkg0'))

        osdeps.should_receive(:availability_of).with('pkg0').once.
            and_return(OSDependencies::UNKNOWN_OS)
        assert(!osdeps.has?('pkg0'))

        osdeps.should_receive(:availability_of).with('pkg0').once.
            and_return(OSDependencies::WRONG_OS)
        assert(!osdeps.has?('pkg0'))

        osdeps.should_receive(:availability_of).with('pkg0').once.
            and_return(OSDependencies::NONEXISTENT)
        assert(!osdeps.has?('pkg0'))

        osdeps.should_receive(:availability_of).with('pkg0').once.
            and_return(OSDependencies::NO_PACKAGE)
        assert(!osdeps.has?('pkg0'))
    end

    def test_resolve_os_dependencies
        osdeps = flexmock(OSDependencies.new)
        osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
            [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkg0']]])
        osdeps.should_receive(:resolve_package).with('pkg1').once.and_return(
            [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkg1']],
             [osdeps.package_handlers['gem'], FOUND_PACKAGES, ['gempkg1']]])
        osdeps.should_receive(:resolve_package).with('pkg2').once.and_return(
            [[osdeps.package_handlers['gem'], FOUND_PACKAGES, ['gempkg2']]])
        expected =
            [[osdeps.os_package_handler, ['pkg0', 'pkg1']],
             [osdeps.package_handlers['gem'], ['gempkg1', 'gempkg2']]]
        assert_equal expected, osdeps.resolve_os_dependencies(['pkg0', 'pkg1', 'pkg2'])

        osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
            [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkg0']]])
        osdeps.should_receive(:resolve_package).with('pkg1').once.and_return(
            [[osdeps.os_package_handler, FOUND_PACKAGES, []]])
        osdeps.should_receive(:resolve_package).with('pkg2').once.and_return(
            [[osdeps.package_handlers['gem'], FOUND_PACKAGES, ['gempkg2']]])
        expected =
            [[osdeps.os_package_handler, ['pkg0']],
             [osdeps.package_handlers['gem'], ['gempkg2']]]
        assert_equal expected, osdeps.resolve_os_dependencies(['pkg0', 'pkg1', 'pkg2'])

        osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(nil)
        osdeps.should_receive(:resolve_package).with('pkg1').never
        osdeps.should_receive(:resolve_package).with('pkg2').never
        assert_raises(Autoproj::OSDependencies::MissingOSDep) { osdeps.resolve_os_dependencies(['pkg0', 'pkg1', 'pkg2']) }

        osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
            [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkg0']]])
        osdeps.should_receive(:resolve_package).with('pkg1').once.and_return(
            [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkg1']],
             [osdeps.package_handlers['gem'], FOUND_PACKAGES, ['gempkg1']]])
        osdeps.should_receive(:resolve_package).with('pkg2').once.and_return(nil)
        expected =
            [[osdeps.os_package_handler, ['pkg0']],
             [osdeps.package_handlers['gem'], ['gempkg1', 'gempkg2']]]
        assert_raises(Autoproj::OSDependencies::MissingOSDep) { osdeps.resolve_os_dependencies(['pkg0', 'pkg1', 'pkg2']) }

        osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
            [[osdeps.os_package_handler, FOUND_NONEXISTENT, ['pkg0']]])
        osdeps.should_receive(:resolve_package).with('pkg1').never
        osdeps.should_receive(:resolve_package).with('pkg2').never
        assert_raises(Autoproj::OSDependencies::MissingOSDep) { osdeps.resolve_os_dependencies(['pkg0', 'pkg1', 'pkg2']) }

        osdeps.should_receive(:resolve_package).with('pkg0').once.and_return(
            [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkg0']]])
        osdeps.should_receive(:resolve_package).with('pkg1').once.and_return(
            [[osdeps.os_package_handler, FOUND_PACKAGES, ['pkg1']],
             [osdeps.package_handlers['gem'], FOUND_NONEXISTENT, ['gempkg1']]])
        osdeps.should_receive(:resolve_package).with('pkg2').never
        assert_raises(Autoproj::OSDependencies::MissingOSDep) { osdeps.resolve_os_dependencies(['pkg0', 'pkg1', 'pkg2']) }
    end

    def test_install
        osdeps = create_osdep(Hash.new)
        osdeps.should_receive(:resolve_os_dependencies).
            once.with(['pkg0', 'pkg1', 'pkg2'].to_set).
            and_return([[osdeps.os_package_handler, ['os0.1', 'os0.2', 'os1']],
                        [osdeps.package_handlers['gem'], [['gem2', '>= 0.9']]]])
        osdeps.os_package_handler.should_receive(:filter_uptodate_packages).
            with(['os0.1', 'os0.2', 'os1']).and_return(['os0.1', 'os1']).once
        # Do not add filter_uptodate_packages to the gem handler to check that
        # #install deals with that just fine
        osdeps.os_package_handler.should_receive(:install).
            with(['os0.1', 'os1'])
        osdeps.package_handlers['gem'].should_receive(:install).
            with([['gem2', '>= 0.9']])

        osdeps.osdeps_mode = 'all'
        osdeps.install(['pkg0', 'pkg1', 'pkg2'])
    end

    def test_resolve_os_dependencies_unsupported_os_non_existent_dependency
        osdeps = create_osdep(Hash.new)
        flexmock(OSDependencies).should_receive(:supported_operating_system?).and_return(false)
        assert_raises(OSDependencies::MissingOSDep) { osdeps.resolve_os_dependencies(['a_package']) }
    end

    def test_resolve_package_availability_unsupported_os_non_existent_dependency
        osdeps = create_osdep(Hash.new)
        flexmock(OSDependencies).should_receive(:supported_operating_system?).and_return(false)
        assert_equal OSDependencies::NO_PACKAGE, osdeps.availability_of('a_package')
    end

    def test_resolve_package_availability_unsupported_os_existent_dependency
        osdeps = create_osdep({ 'a_package' => { 'an_os' => 'bla' }})
        flexmock(OSDependencies).should_receive(:supported_operating_system?).and_return(false)
        assert_equal OSDependencies::AVAILABLE, osdeps.availability_of('a_package')
    end

    def test_resolve_os_dependencies_unsupported_os_existent_dependency
        osdeps = create_osdep({ 'a_package' => { 'an_os' => 'bla' }})
        flexmock(OSDependencies).should_receive(:supported_operating_system?).and_return(false)
        assert_equal [[osdeps.os_package_handler, ['a_package']]], osdeps.resolve_os_dependencies(['a_package'])
    end

    DATA_DIR = File.expand_path('data', File.dirname(__FILE__))
    def test_os_from_os_release_returns_nil_if_the_os_release_file_is_not_found
        assert !Autoproj::OSDependencies.os_from_os_release('does_not_exist')
    end
    def test_os_from_os_release_handles_quoted_and_unquoted_fields
        names, versions = Autoproj::OSDependencies.os_from_os_release(
            File.join(DATA_DIR, 'os_release.with_missing_optional_fields'))
        assert_equal ['name'], names
        assert_equal ['version_id'], versions
    end
    def test_os_from_os_release_handles_optional_fields
        names, versions = Autoproj::OSDependencies.os_from_os_release(
            File.join(DATA_DIR, 'os_release.with_missing_optional_fields'))
        assert_equal ['name'], names
        assert_equal ['version_id'], versions
    end
    def test_os_from_os_release_parses_the_version_field
        _, versions = Autoproj::OSDependencies.os_from_os_release(
            File.join(DATA_DIR, 'os_release.with_complex_version_field'))
        assert_equal ['version_id', 'version', 'codename', 'codename_bis'], versions
    end
    def test_os_from_os_release_removes_duplicate_values
        names, versions = Autoproj::OSDependencies.os_from_os_release(
            File.join(DATA_DIR, 'os_release.with_duplicate_values'))
        assert_equal ['id'], names
        assert_equal ['version_id', 'codename'], versions
    end
    def test_os_from_lsb_returns_nil_if_lsb_release_is_not_found_in_path
        flexmock(ENV).should_receive('[]').with('PATH').and_return('')
        assert !Autoproj::OSDependencies.os_from_lsb
    end

    def test_merge_issues_a_warning_if_two_definitions_differ_by_the_operating_system_packages
        Autoproj::OSDependencies.operating_system = [['os0'], []]
        osdeps0 = Autoproj::OSDependencies.new
        osdeps0.definitions['pkg'] = Hash['os0' => ['osdep0'], 'gem' => ['gem0']]
        osdeps0.sources['pkg'] = 'bla/bla'
        osdeps1 = Autoproj::OSDependencies.new
        osdeps1.definitions['pkg'] = Hash['os0' => ['osdep1'], 'gem' => ['gem0']]
        osdeps1.sources['pkg'] = 'bla/bla'
        flexmock(Autoproj).should_receive(:warn).once
        osdeps0.merge(osdeps1)
    end
    def test_merge_issues_a_warning_if_two_definitions_differ_by_an_os_independent_package
        Autoproj::OSDependencies.operating_system = [['os0'], []]
        osdeps0 = Autoproj::OSDependencies.new
        osdeps0.definitions['pkg'] = Hash['os0' => ['osdep0'], 'gem' => ['gem0']]
        osdeps0.sources['pkg'] = 'bla/bla'
        osdeps1 = Autoproj::OSDependencies.new
        osdeps1.definitions['pkg'] = Hash['os0' => ['osdep0'], 'gem' => ['gem1']]
        osdeps1.sources['pkg'] = 'bla/bla'
        flexmock(Autoproj).should_receive(:warn).once
        osdeps0.merge(osdeps1)
    end
    def test_merge_does_not_issue_a_warning_if_two_definitions_are_identical_for_the_local_operating_system
        Autoproj::OSDependencies.operating_system = [['os0'], []]
        osdeps0 = Autoproj::OSDependencies.new
        osdeps0.definitions['pkg'] = Hash['os0' => ['osdep0'], 'gem' => ['gem0'], 'os1' => ['osdep0']]
        osdeps0.sources['pkg'] = 'bla/bla'
        osdeps1 = Autoproj::OSDependencies.new
        osdeps1.definitions['pkg'] = Hash['os0' => ['osdep0'], 'gem' => ['gem0'], 'os1' => ['osdep1']]
        osdeps1.sources['pkg'] = 'bla/bla'
        flexmock(Autoproj).should_receive(:warn).never
        osdeps0.merge(osdeps1)
    end
end

