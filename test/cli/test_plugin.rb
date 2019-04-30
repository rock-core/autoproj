require 'autoproj/test'
require 'autoproj/aruba_minitest'

module Autoproj
    module CLI
        describe "plugin" do
            include ArubaMinitest

            before do
                @autoproj_bin_dir = File.expand_path(
                    File.join("..", "..", "bin"), __dir__)
                run_command_and_stop "#{Gem.ruby} "\
                    "#{File.join(@autoproj_bin_dir, "autoproj_install")} "\
                    "--no-interactive",
                    exit_timeout: 120
                @autoproj_bin = File.join(expand_path('.'),
                    ".autoproj", "bin", "autoproj")
            end

            it "installs a new plugin on the wokspace" do
                run_command_and_stop "#{@autoproj_bin} plugin install autoproj-git"
                run_command_and_stop "#{@autoproj_bin} help git"
            end

            it "deinstalls a plugin" do
                run_command_and_stop "#{@autoproj_bin} plugin remove autoproj-git"
                cmd = run_command "#{@autoproj_bin} help git",
                    fail_on_error: false
                assert cmd.exit_status != 0
            end
        end
    end
end

