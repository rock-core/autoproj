require 'autoproj/test'
require 'autoproj/cli/which'

module Autoproj
    module CLI
        describe Which do
            include Autoproj::SelfTest;
            before do
                ws_create
                @cli = Which.new(ws)
                flexmock(@cli).should_receive(:initialize_and_load)
            end

            it "displays a given full path if it exists, regardless of PATH" do
                ws.env.clear 'PATH'
                path = File.join(ws.root_dir, 'test')
                FileUtils.touch path
                out, err = capture_io do
                    @cli.run path
                end
                assert_equal "#{path}\n", out
            end

            it "displays an error if a given full path does not exist, and exits with error" do
                path = File.join(ws.root_dir, 'test')
                flexmock(Autoproj).should_receive(:error).with("given command `#{path}` does not exist").
                    once
                assert_raises(SystemExit) do
                    @cli.run path
                end
            end

            it "displays the resolved full path if found" do
                ws.env.set 'PATH', ws.root_dir
                path = File.join(ws.root_dir, 'test')
                FileUtils.touch path
                out, err = capture_io do
                    @cli.run 'test'
                end
                assert_equal "#{path}\n", out
            end

            it "displays an error if the path cannot be resolved, and exits with error" do
                flexmock(Autoproj).should_receive(:error).with("cannot resolve `test` in the workspace").
                    once
                assert_raises(SystemExit) do
                    @cli.run 'test'
                end
            end
        end
    end
end

