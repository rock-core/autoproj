$LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))
require 'test/unit'
require 'rubotics/system'

class TC_Debian < Test::Unit::TestCase
    def test_debian_detection
        assert Rubotics.on_debian?
    end

    def test_apt_version
        apt_version = Rubotics.apt_version
        version_string = apt_version.join(".")
        assert `apt-get -v` =~ /#{Regexp.quote(version_string)}/
    end
end

