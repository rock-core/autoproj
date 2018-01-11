require 'autoproj/test'
require 'autoproj/cli/exec'

module Autoproj
    module CLI
        describe Exec do
            before do
                ws_create
                @cli = Exec.new(ws)
                flexmock(@cli).should_receive(:initialize_and_load)
            end

            it "passes the full environment, program and the arguments to the exec'd process" do
                flexmock(ws).should_receive(:which).with("path").
                    and_return('/resolved/path')
                env = flexmock
                flexmock(ws).should_receive(:full_env => flexmock(resolved_env: env))
                flexmock(Process).should_receive(:exec).with(env, "/resolved/path", 'args').once
                @cli.run('path', 'args')
            end

            it "re-raises any exception raised by Process as a CLIInvalidArguments" do
                flexmock(ws).should_receive(:which).with("path").
                    and_return('/resolved/path')
                flexmock(Process).should_receive(:exec).
                    and_raise(RuntimeError.new("ENOENT"))
                e = assert_raises(CLIInvalidArguments) do
                    @cli.run('path')
                end
                assert_equal "ENOENT", e.message
            end

            it "re-raises a ExecutableNotFound originally raised by Workspace#which" do
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


