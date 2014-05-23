$LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))
require 'test/unit'
require 'autoproj'
require 'flexmock/test_unit'
require 'set'

class TC_Manifest < Test::Unit::TestCase
    DATA_DIR = File.expand_path('data', File.dirname(__FILE__))
    include Autoproj

    def test_each_package_set
        Dir.chdir(File.join(DATA_DIR, 'test_manifest', 'autoproj')) do
            manifest = Manifest.load(File.join(DATA_DIR, 'test_manifest', 'autoproj', 'manifest'))
            sources  = manifest.each_package_set(false).to_set

            test_data      = "#{DATA_DIR}/test_manifest"
            test_data_name = test_data.gsub '/', '_'

            local_set = sources.find { |pkg_set| pkg_set.name == 'local_set' }
            assert local_set
            assert_equal "#{test_data}/autoproj/local_set", local_set.raw_local_dir
            assert local_set.local?

            remote_set = sources.find { |pkg_set| pkg_set.name == "git:remote2.git branch=next"}
            assert remote_set, "available package sets: #{sources.map(&:name)}"
            assert_equal "#{test_data}/.remotes/git__home_doudou_dev_rock_master_tools_autoproj_test_data_test_manifest_remote2_git", remote_set.raw_local_dir
        end
    end

    def test_single_expansion_uses_provided_definitions
        flexmock(Autoproj).should_receive(:user_config).never
        assert_equal "a_variable=val", Autoproj.single_expansion("a_variable=$CONST", 'CONST' => 'val')
        assert_equal "val", Autoproj.single_expansion("$CONST", 'CONST' => 'val')
    end

    def test_single_expansion_uses_user_config
        flexmock(Autoproj).should_receive(:user_config).with("CONST").and_return("val")
        assert_equal "a_variable=val", Autoproj.single_expansion("a_variable=$CONST", Hash.new)
        assert_equal "val", Autoproj.single_expansion("$CONST", Hash.new)
    end

    def test_single_expansion_handle_quoted_dollar_sign
        flexmock(Autoproj).should_receive(:user_config).with("CONST").and_return("val")
        assert_equal "a_variable=$CONST", Autoproj.single_expansion("a_variable=\\$CONST", Hash.new)
        assert_equal "$CONST", Autoproj.single_expansion("\\$CONST", Hash.new)
    end
end

