# frozen_string_literal: true

require "autoproj/test"

module Autoproj
    describe RosConditionParser do
        before do
            @context = {}
        end
        def condition(input)
            RosConditionParser.new do |var|
                Autoproj.expand(var, @context)
            rescue StandardError
                ""
            end .evaluate(input)
        end
        it "expands variables" do
            @context["FOO"] = "bar"
            assert condition("$FOO == bar")
        end
        it "evaluates unset variables to empty string" do
            assert condition("$FOO == ''")
        end
        it "implements all comparison operators" do
            assert condition("a == a")
            assert condition("a != b")
            assert condition("2 > 1")
            assert condition("2 >= 2")
            assert condition("1 < 2")
            assert condition("1 <= 1")
        end
        it "evaluates multiple conditions" do
            assert condition("a == a and b == b")
        end
        it "does not require spaces between tokens" do
            assert condition("a==a")
        end
        it "ignores spaces and tabs" do
            assert condition("   a\t ==  a  ")
        end
        it "differentiates operators and literals" do
            assert condition('"and" == "or" or "or" == "or"')
        end
        it "processes parentheses" do
            refute condition("1 == 2 and (1 == 2 or 1 == 1)")
            assert condition("1 == 2 and 1 == 2 or 1 == 1")
        end
        it "allows nested parentheses" do
            assert condition("1 == 2 or (1 == 2 and 1 == 1 or 1 == 1)")
            refute condition("1 == 2 or (1 == 2 and (1 == 1 or 1 == 1))")
            refute condition("1 == 2 or ((1 == 2 and (1 == 1 or 1 == 1)))")
        end
        it "handles quotes" do
            assert condition %q('some phrase' == "some phrase")
        end
        it "raises if an invalid token is used" do
            assert_raises(ConfigError) { condition("inv%alid == c") }
            assert_raises(ConfigError) { condition("$1 == c") }
        end
        it "handles literals that contain reserved words" do
            @context["FOO"] = "band"
            assert condition("$FOO == band")

            @context["FOO"] = "fortress"
            assert condition("$FOO == fortress")

            @context["FOO"] = "orchid"
            assert condition("$FOO == orchid")
        end
        it "allows any character between quotes" do
            assert condition("'inv%alid' == 'inv%alid'")
        end
        it "raises if syntax is invalid" do
            assert_raises(ConfigError) { condition("2 > > 1") }
            assert_raises(ConfigError) { condition("2 2 > 1") }
            assert_raises(ConfigError) { condition("a ==") }
            assert_raises(ConfigError) { condition("== b") }
            assert_raises(ConfigError) { condition("(a == b") }
            assert_raises(ConfigError) { condition("a == b)") }
            assert_raises(ConfigError) { condition("a ) b") }
            assert_raises(ConfigError) { condition("a ( b") }
            assert_raises(ConfigError) { condition("a () b") }
            assert_raises(ConfigError) { condition("a b c") }
            assert_raises(ConfigError) { condition("and or and") }
            assert_raises(ConfigError) { condition("1 1 (") }
            assert_raises(ConfigError) { condition("1 1 )") }
            assert_raises(ConfigError) { condition(") 1 1") }
            assert_raises(ConfigError) { condition("( 1 1") }
            assert_raises(ConfigError) { condition("1 1 ==") }
        end
    end
end
