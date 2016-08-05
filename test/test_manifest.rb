require 'autoproj/test'
require 'set'

module Autoproj
    describe Manifest do
        attr_reader :manifest
        before do
            ws_create
            @manifest = ws.manifest
            manifest.os_package_resolver.operating_system = [['test_os_name'], ['test_os_version']]
            manifest
        end

        describe "#resolve_package_name" do
            it "resolves source packages" do
                manifest.register_package(Autobuild::Package.new('test'))
                assert_equal [[:package, 'test']], manifest.resolve_package_name('test')
            end
            it "resolves OS packages" do
                manifest.os_package_resolver.merge OSPackageResolver.new('test' => Hash['test_os_name' => 'bla'])
                assert_equal [[:osdeps, 'test']], manifest.resolve_package_name('test')
            end
            it "resolves OS packages into its overrides on OSes where the package is not available" do
                manifest.register_package(Autobuild::Package.new('test_src'))
                manifest.add_osdeps_overrides 'test', package: 'test_src'
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::WRONG_OS)
                assert_equal [[:package, 'test_src']], manifest.resolve_package_name('test')
            end
            it "resolves to the OS package if both an OS and source package are available at the same time" do
                manifest.register_package(Autobuild::Package.new('test_src'))
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::AVAILABLE)
                assert_equal [[:osdeps, 'test']], manifest.resolve_package_name('test')
            end
            it "automatically resolves OS packages into a source package with the same name if the package is not available" do
                manifest.register_package(Autobuild::Package.new('test'))
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::WRONG_OS)
                assert_equal [[:package, 'test']], manifest.resolve_package_name('test')
            end
            it "resolves OS packages into its overrides if the override is forced" do
                manifest.register_package(Autobuild::Package.new('test'))
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::AVAILABLE)
                manifest.add_osdeps_overrides 'test', force: true
                assert_equal [[:package, 'test']], manifest.resolve_package_name('test')
            end
            it "resolves OS packages into its overrides if the override is forced" do
                manifest.register_package(Autobuild::Package.new('test_src'))
                manifest.add_osdeps_overrides 'test', package: 'test_src', force: true
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::AVAILABLE)
                assert_equal [[:package, 'test_src']], manifest.resolve_package_name('test')
            end
            it "resolves an OS package that is explicitely marked as ignored" do
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::IGNORE)
                assert_equal [[:osdeps, 'test']], manifest.resolve_package_name('test')
            end
            it "raises if a package is undefined" do
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::NO_PACKAGE)
                e = assert_raises(PackageNotFound) { manifest.resolve_package_name('test') }
                assert_match(/test is not an osdep and it cannot be resolved as a source package/, e.message)
            end
            it "raises if a package is defined as an osdep but it is not available on the local operating system" do
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::WRONG_OS)
                e = assert_raises(PackageNotFound) { manifest.resolve_package_name('test') }
                assert_match(/test is an osdep, but it is not available for this operating system and it cannot be resolved as a source package/, e.message)
            end
            it "raises if a package is defined as an osdep but it is explicitely marked as non existent" do
                flexmock(manifest.os_package_resolver).should_receive(:availability_of).with('test').
                    and_return(OSPackageResolver::NONEXISTENT)
                e = assert_raises(PackageNotFound) { manifest.resolve_package_name('test') }
                assert_match(/test is an osdep, but it is explicitely marked as 'nonexistent' for this operating system and it cannot be resolved as a source package/, e.message)
            end
        end
    end
end

