require "autoproj/test"
require "autoproj/aruba_minitest"

module Autoproj
    module CLI
        describe "plugin" do
            include ArubaMinitest

            before do
                skip "long test" if skip_long_tests?

                @home_dir = make_tmpdir
                unset_bundler_env_vars
                set_environment_variable "HOME", @home_dir
                @autoproj_bin_dir = File.expand_path(
                    File.join("..", "..", "bin"), __dir__
                )
                gemfile = generate_local_gemfile
                run_command_and_stop(
                    "#{Gem.ruby} "\
                    "#{File.join(@autoproj_bin_dir, 'autoproj_install')} "\
                    "--no-interactive --gemfile=#{gemfile}",
                    exit_timeout: 120
                )
                @bundle_bin = File.join(expand_path("."),
                                        ".autoproj", "bin", "bundle")
                @autoproj_bin = File.join(expand_path("."),
                                          ".autoproj", "bin", "autoproj")
            end

            it "installs a new plugin on the wokspace" do
                run_command_and_stop "#{@autoproj_bin} plugin install autoproj-ci"
                run_command_and_stop "#{@autoproj_bin} help ci"
            end

            it "installs a new plugin from git" do
                run_command_and_stop "#{@autoproj_bin} plugin install autoproj-ci "\
                                     "--git https://github.com/rock-core/autoproj-ci"
                run_command_and_stop "#{@autoproj_bin} help ci"
            end

            it "installs a new plugin from git, and allows to specify the branch" do
                run_command_and_stop(
                    "git clone https://github.com/rock-core/autoproj-ci"
                )
                cd "autoproj-ci"
                run_command_and_stop("git branch autoproj-test-suite")
                head = run_command_and_stop("git rev-parse HEAD").stdout.strip
                # Change HEAD and master
                run_command_and_stop("git config user.email you@example.com")
                run_command_and_stop("git config user.name Example")
                run_command_and_stop("git commit --allow-empty -m \"blank commit\"")
                cd ".."

                run_command_and_stop "#{@autoproj_bin} plugin install autoproj-ci "\
                                     "--git #{expand_path('autoproj-ci')} "\
                                     "--branch autoproj-test-suite"
                output = run_command_and_stop("#{@bundle_bin} show autoproj-ci")
                         .stdout.strip
                assert_match(%r{bundler/gems/autoproj-ci-#{head[0, 5]}}, output)
            end

            it "deinstalls a plugin" do
                run_command_and_stop "#{@autoproj_bin} plugin install autoproj-ci"
                run_command_and_stop "#{@autoproj_bin} plugin remove autoproj-ci"
                cmd = run_command "#{@autoproj_bin} help git",
                                  fail_on_error: false
                assert cmd.exit_status != 0
            end

            def run_command(cmd, **kw_args)
                Bundler.with_unbundled_env do
                    super
                end
            end
        end
    end
end
