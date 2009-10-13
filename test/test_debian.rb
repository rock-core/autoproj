$LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))
require 'test/unit'
require 'autoproj/system'

class TC_Debian < Test::Unit::TestCase
    def test_debian_detection
        assert Autoproj.on_debian?
    end

    def test_apt_version
        apt_version = Autoproj.apt_version
        version_string = apt_version.join(".")
        assert `apt-get -v` =~ /#{Regexp.quote(version_string)}/
    end
end

