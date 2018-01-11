require 'autoproj/test'
require 'autoproj/cli/which'

module Autoproj
    module CLI
        describe Which do
            before do
                ws_create
                @cli = Which.new(ws)
                flexmock(@cli).should_receive(:initialize_and_load)
            end

            it "displays the value returned by Workspace#which" do
                flexmock(ws).should_receive(:which).with("path").
                    and_return('/resolved/path')
                out, err = capture_io do
                    @cli.run('path')
                end
                assert_equal "/resolved/path\n", out
            end

            it "re-raises an ExecutableNotFound exception raied by Workspace#which as CLIInvalidArguments" do
                flexmock(ws).should_receive(:which).with("path").
                    and_raise(Workspace::ExecutableNotFound.new("cannot find"))
                e = assert_raises(CLIInvalidArguments) do
                    @cli.run('path')
                end
                assert_equal "cannot find", e.message
            end
        end
    end
end

