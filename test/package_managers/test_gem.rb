require 'autoproj/test'
require 'autoproj/package_managers/gem_manager'

module Autoproj
    module PackageManagers
        describe GemManager do
            FOUND_PACKAGES = OSPackageResolver::FOUND_PACKAGES
            FOUND_NONEXISTENT = OSPackageResolver::FOUND_NONEXISTENT

            attr_reader :gem_manager
            attr_reader :gem_fetcher
            attr_reader :gem_spec

            def setup
                OSPackageResolver.operating_system = [['test', 'debian', 'default'], ['v1.0', 'v1', 'default']]

                ws = flexmock
                @gem_manager = GemManager.new(ws)
                @gem_fetcher = flexmock("fake gem fetcher")
                gem_manager.gem_fetcher = gem_fetcher
                @gem_spec = flexmock(Gem::Specification)
                Autobuild.programs['gem'] = 'mygem'
                super
            end

            def teardown
                super
                GemManager.with_prerelease = false
                GemManager.with_doc = false
                Autobuild.programs['gem'] = nil
            end

            let(:fake_installed_package) { flexmock("fake installed pgk0", :version => Gem::Version.new("1.0.0")) }

            def test_filter_uptodate_packages_passes_prerelease_flag
                GemManager.with_prerelease = true

                dep = Gem::Dependency.new("pkg0", Gem::Requirement.new('>= 0.9'))
                gem_spec.should_receive(:find_by_name).
                    with('pkg0', eq(Gem::Requirement.new('>= 0.9'))).and_return(fake_installed_package)
                gem_fetcher.should_receive("find_matching").with(dep, true, true).
                    and_return([[["pkg0", Gem::Version.new("0.8")], nil]])
                gem_fetcher.should_receive("find_matching").with(dep, false, true, true).
                    and_return([[["pkg0", Gem::Version.new("1.1.0.b1")], nil]])
                assert_equal [['pkg0', '>= 0.9']], gem_manager.filter_uptodate_packages([['pkg0', '>= 0.9']])
            end

            def test_filter_uptodate_packages_with_no_installed_package
                dep = Gem::Dependency.new("pkg0", Gem::Requirement.new('>= 0'))
                gem_spec.should_receive(:find_by_name).
                    with('pkg0', eq(Gem::Requirement.new('>= 0'))).and_raise(Gem::LoadError)
                gem_fetcher.should_receive("find_matching").with(dep, true, true, false).
                    and_return([[["pkg0", Gem::Version.new("1.0.0")], nil]])
                assert_equal [['pkg0']], gem_manager.filter_uptodate_packages([['pkg0']])
            end

            def test_filter_uptodate_packages_passes_version_specification
                dep = Gem::Dependency.new("pkg0", Gem::Requirement.new('>= 0.9'))
                gem_spec.should_receive(:find_by_name).
                    with('pkg0', eq(Gem::Requirement.new('>= 0.9'))).and_raise(Gem::LoadError)
                gem_fetcher.should_receive("find_matching").with(dep, true, true, false).
                    and_return([[["pkg0", Gem::Version.new("1.0.0")], nil]])
                assert_equal [['pkg0', '>= 0.9']], gem_manager.filter_uptodate_packages([['pkg0', '>= 0.9']])
            end

            def test_filter_uptodate_packages_with_outdated_package
                dep = Gem::Dependency.new("pkg0", Gem::Requirement.new('>= 0.9'))
                gem_spec.should_receive(:find_by_name).
                    with('pkg0', eq(Gem::Requirement.new('>= 0.9'))).and_return(fake_installed_package)
                gem_fetcher.should_receive("find_matching").with(dep, true, true).
                    and_return([[["pkg0", Gem::Version.new("1.1.0")], nil]])
                assert_equal [['pkg0', '>= 0.9']], gem_manager.filter_uptodate_packages([['pkg0', '>= 0.9']])
            end

            def test_filter_uptodate_packages_with_same_package
                dep = Gem::Dependency.new("pkg0", Gem::Requirement.new('>= 0'))
                gem_spec.should_receive(:find_by_name).
                    with('pkg0', eq(Gem::Requirement.new('>= 0'))).and_return(fake_installed_package)
                gem_fetcher.should_receive("find_matching").with(dep, true, true).
                    and_return([[["pkg0", Gem::Version.new("1.0.0")], nil]])
                assert_equal [], gem_manager.filter_uptodate_packages([['pkg0']])
            end

            def test_filter_uptodate_packages_with_newer_installed_package
                dep = Gem::Dependency.new("pkg0", Gem::Requirement.new('>= 0.9'))
                gem_spec.should_receive(:find_by_name).
                    with('pkg0', eq(Gem::Requirement.new('>= 0.9'))).
                    and_return(fake_installed_package)
                gem_fetcher.should_receive("find_matching").with(dep, true, true).
                    and_return([[["pkg0", Gem::Version.new("1.0.0")], nil]])
                assert_equal [], gem_manager.filter_uptodate_packages([['pkg0', '>= 0.9']])
            end

            # Helper to have a shortcut for the default install options
            def default_install_options
                GemManager.default_install_options
            end

            def test_install_packages
                GemManager.with_prerelease = false
                GemManager.with_doc = false
                subprocess = flexmock(Autobuild::Subprocess)

                packages = [['pkg0'], ['pkg1', '>= 0.5'], ['pkg2'], ['pkg3', '>= 0.9']]
                subprocess.should_receive(:run).
                    with(any, any, any, any, 'mygem', 'install', *default_install_options, '--no-rdoc', '--no-ri', 'pkg0', 'pkg2', Hash).once
                subprocess.should_receive(:run).
                    with(any, any, any, any, 'mygem', 'install', *default_install_options, '--no-rdoc', '--no-ri', 'pkg1', '-v', '>= 0.5', Hash).once
                subprocess.should_receive(:run).
                    with(any, any, any, any, 'mygem', 'install', *default_install_options, '--no-rdoc', '--no-ri', 'pkg3', '-v', '>= 0.9', Hash).once
                gem_manager.install(packages)
            end

            def test_install_packages_with_doc
                GemManager.with_prerelease = false
                GemManager.with_doc = true
                subprocess = flexmock(Autobuild::Subprocess)

                packages = [['pkg0']]
                subprocess.should_receive(:run).
                    with(any, any, any, any, 'mygem', 'install', *default_install_options, 'pkg0', Hash).once
                gem_manager.install([['pkg0']])
            end

            def test_install_packages_with_prerelease
                GemManager.with_prerelease = true
                GemManager.with_doc = true
                subprocess = flexmock(Autobuild::Subprocess)

                subprocess.should_receive(:run).
                    with(any, any, any, any, 'mygem', 'install', *default_install_options, '--prerelease', 'pkg0', Hash).once
                gem_manager.install([['pkg0']])
            end

            def test_install_packages_disabled_and_silent
                GemManager.with_prerelease = true
                GemManager.with_doc = true
                subprocess = flexmock(Autobuild::Subprocess)
                gem_manager.enabled = false
                gem_manager.silent = true

                subprocess.should_receive(:run).never
                flexmock(STDIN).should_receive(:readline).never.and_return
                gem_manager.install([['pkg0']])
            end

            def test_install_packages_disabled_and_not_silent
                GemManager.with_prerelease = true
                GemManager.with_doc = true
                subprocess = flexmock(Autobuild::Subprocess)
                gem_manager.enabled = false
                gem_manager.silent = false

                subprocess.should_receive(:run).never
                flexmock(STDIN).should_receive(:readline).once.and_return
                gem_manager.install([['pkg0']])
            end
        end
    end
end


