require 'autoproj/test'
require 'autoproj/cli/test'

module Autoproj
    module CLI
        describe Test do
            attr_reader :cli
            attr_reader :ws
            before do
                @ws = ws_create
                @one = ws_add_package_to_layout :cmake, 'one'
                @two = ws_add_package_to_layout :cmake, 'two'
                @three = ws_define_package :cmake, 'three'
                @cli = Test.new(ws)
                flexmock(cli)
            end

            describe "#run" do
                it "validates user selection" do
                    cli.run(%w[one two])
                end
                it "throws if one of the packages is not defined" do
                    assert_raises(Autoproj::CLI::CLIInvalidArguments) do
                        cli.run(%w[one two foo])
                    end
                end
                it "throws if the selected package is excluded from build" do
                    ws.manifest.exclude_package('two', 'test')
                    assert_raises(Autoproj::CLI::CLIInvalidSelection) do
                        cli.run(%w[two])
                    end
                end
                it "throws if the selected package is not in the layout" do
                    ws.manifest.ignore_package('three')
                    assert_raises(Autoproj::CLI::CLIInvalidArguments) do
                        cli.run(%w[three])
                    end
                end
            end
        end
    end
end
