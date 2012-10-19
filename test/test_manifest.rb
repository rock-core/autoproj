$LOAD_PATH.unshift File.expand_path('../lib', File.dirname(__FILE__))
require 'test/unit'
require 'autoproj'
require 'flexmock/test_unit'
require 'set'

class TC_Manifest < Test::Unit::TestCase
    DATA_DIR = File.expand_path('data', File.dirname(__FILE__))
    include Autoproj

    def test_each_sources
        Dir.chdir(File.join(DATA_DIR, 'test_manifest', 'autoproj')) do
            manifest = Manifest.load(File.join(DATA_DIR, 'test_manifest', 'autoproj', 'manifest'))
            sources  = manifest.each_source.to_set

            test_data      = "#{DATA_DIR}/test_manifest"
            test_data_name = test_data.gsub '/', '_'

            expected = [
                 ["#{test_data_name}_autoproj_local", "local",
                    "#{test_data}/autoproj/local",
                    "#{test_data}/autoproj/local",
                    {}],
                 ["#{test_data_name}_remote1_git", "git",
                    "#{test_data}/remote1.git",
                    "#{test_data}/autoproj/remotes/_home_doudou_src_autoproj_test_data_test_manifest_remote1_git",
                    {}],
                 ["#{test_data_name}_remote2_git", "git",
                    "#{test_data}/remote2.git",
                    "#{test_data}/autoproj/remotes/_home_doudou_src_autoproj_test_data_test_manifest_remote2_git",
                    {:branch=>"next"}]
            ]

            assert_equal(expected.to_set, sources)
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

