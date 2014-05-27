$LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))
require 'test/unit'
require 'autoproj'
require 'flexmock/test_unit'

class TC_OSDependencies_AptDpkgManager < Test::Unit::TestCase
    def test_status_file_parsing
        file = File.expand_path("apt-dpkg-status", File.dirname(__FILE__))
        mng = Autoproj::PackageManagers::AptDpkgManager.new(file)
        assert mng.installed?('installed-package')
        assert !mng.installed?('noninstalled-package')
    end

    def test_status_file_parsing_is_robust_to_invalid_utf8
        Tempfile.open 'osdeps_aptdpkg' do |io|
            io.puts "Package: \x80\nStatus: installed ok install\n\nPackage: installed\nStatus: installed ok install"
            io.flush
            mng = Autoproj::PackageManagers::AptDpkgManager.new(io.path)
            mng.installed?('installed')
        end
    end

    def test_status_file_parsing_last_entry_installed
        file = File.expand_path("apt-dpkg-status.installed-last", File.dirname(__FILE__))
        mng = Autoproj::PackageManagers::AptDpkgManager.new(file)
        assert mng.installed?('installed-package')
    end

    def test_status_file_parsing_last_entry_not_installed
        file = File.expand_path("apt-dpkg-status.noninstalled-last", File.dirname(__FILE__))
        mng = Autoproj::PackageManagers::AptDpkgManager.new(file)
        assert !mng.installed?('noninstalled-package')
    end

    def test_status_file_parsing_not_there_means_not_installed
        file = File.expand_path("apt-dpkg-status.noninstalled-last", File.dirname(__FILE__))
        mng = Autoproj::PackageManagers::AptDpkgManager.new(file)
        assert !mng.installed?('non-existent-package')
    end
end

