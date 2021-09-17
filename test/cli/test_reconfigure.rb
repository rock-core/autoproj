require "autoproj/test"
require "autoproj/aruba_minitest"
require "autoproj/cli/reconfigure"

module Autoproj
    module CLI
        describe Reconfigure do
            include Autoproj::ArubaMinitest

            before do
                @ws = ws_create(make_tmpdir, partial_config: true)
                set_environment_variable "AUTOPROJ_CURRENT_ROOT", ws.root_dir
                @autoproj_bin = File.expand_path(
                    File.join("..", "..", "bin", "autoproj"), __dir__
                )
            end
            describe "#reconfigure" do
                it "reconfigure should run interactively" do
                    cmd = run_command "#{@autoproj_bin} reconfigure"
                    cmd.stdin.write("\n" * 100)
                    cmd.stop
                    assert_equal 0, cmd.exit_status
                end
                it "reconfigure should run non interactively" do
                    cmd = run_command_and_stop "#{@autoproj_bin} reconfigure "\
                                               "--interactive=f"
                    assert_equal 0, cmd.exit_status
                end
            end
        end
    end
end
