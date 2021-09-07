require "autoproj/test"
require "autoproj/aruba_minitest"

module Autoproj
    module CLI
        describe "envsh" do
            include ArubaMinitest

            before do
                @home_dir = make_tmpdir
                unset_bundler_env_vars
                set_environment_variable "HOME", @home_dir
                @autoproj_bin_dir = File.expand_path(
                    File.join("..", "..", "bin"), __dir__
                )
                run_command_and_stop "#{Gem.ruby} "\
                    "#{File.join(@autoproj_bin_dir, 'autoproj_install')} "\
                    "--no-interactive --gemfile '#{gemfile_aruba}'",
                                     exit_timeout: 120
                @autoproj_bin = File.join(expand_path("."),
                                          ".autoproj", "bin", "autoproj")
            end

            it "generates the env.sh file and the installation manifest" do
                FileUtils.rm_f expand_path("env.sh")
                FileUtils.rm_f expand_path(File.join(".autoproj", "installation-manifest"))
                run_command_and_stop "#{@autoproj_bin} envsh --no-interactive"
                assert File.file?(expand_path("env.sh"))
                assert File.file?(expand_path(File.join(".autoproj", "installation-manifest")))
            end
        end
    end
end
