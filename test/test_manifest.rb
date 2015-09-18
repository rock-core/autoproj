require 'autoproj/test'
require 'set'

class TC_Manifest < Minitest::Test
    DATA_DIR = File.expand_path('data', File.dirname(__FILE__))
    include Autoproj

    def test_single_expansion_uses_provided_definitions
        assert_equal "a_variable=val", Autoproj.single_expansion("a_variable=$CONST", 'CONST' => 'val', config: nil)
        assert_equal "val", Autoproj.single_expansion("$CONST", 'CONST' => 'val')
    end

    def test_single_expansion_uses_the_configuration_object
        config = flexmock
        config.should_receive(:get).with('CONST').and_return('val')
        assert_equal "a_variable=val", Autoproj.single_expansion("a_variable=$CONST", Hash.new, config: config)
        assert_equal "val", Autoproj.single_expansion("$CONST", Hash.new, config: config)
    end

    def test_single_expansion_handle_quoted_dollar_sign
        flexmock(Autoproj).should_receive(:user_config).with("CONST").and_return("val")
        assert_equal "a_variable=$CONST", Autoproj.single_expansion("a_variable=\\$CONST", Hash.new)
        assert_equal "$CONST", Autoproj.single_expansion("\\$CONST", Hash.new)
    end
end

