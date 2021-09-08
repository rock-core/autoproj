require "autoproj/test"
require "autoproj/aruba_minitest"

module Autoproj
    module CLI
        describe "bootstrap" do
            include ArubaMinitest

            before do
                skip "long test" if skip_long_tests?

                @autoproj_bin_dir = File.expand_path(
                    File.join("..", "..", "bin"), __dir__
                )
                @gem_home = make_tmpdir
            end

            %w[bootstrap install].each do |mode|
                describe "interactivity in #{mode} mode" do
                    it "is interactive by default" do
                        output = assert_bootstrap_is_interactive(mode: mode)
                        assert_match(/build_option.rb:.*:in `readline': end of file reached/,
                                     output)
                    end

                    it "is not interactive if --no-interactive is given on the command line" do
                        refute_bootstrap_is_interactive("--no-interactive", mode: mode)
                    end

                    it "is not interactive if AUTOPROJ_NONINTERACTIVE is set" do
                        refute_bootstrap_is_interactive(
                            { "AUTOPROJ_NONINTERACTIVE" => "1" }, mode: mode
                        )
                    end
                end
            end

            describe "empty dir check" do
                before do
                    FileUtils.touch expand_path("some_file")
                    # Need to feed some seed config so that we don't fail
                    # on config questions as opposed to the non-empty check
                    File.open(expand_path("seed-config.yml"), "w") do |io|
                        YAML.dump(
                            { "osdeps_mode" => "all", "apt_dpkg_update" => true }, io
                        )
                    end
                end

                it "tests by default that the install dir is empty" do
                    output = assert_bootstrap_is_interactive(
                        "--seed-config", "seed-config.yml", mode: "bootstrap"
                    )
                    assert_match(/check_root_dir_empty/, output)
                end

                it "does not run the check if --no-interactive is given" do
                    refute_bootstrap_is_interactive("--no-interactive", mode: "bootstrap")
                end

                it "does not run the check if AUTOPROJ_NONINTERACTIVE is set" do
                    refute_bootstrap_is_interactive(
                        { "AUTOPROJ_NONINTERACTIVE" => "1" }, mode: "bootstrap"
                    )
                end

                it "does not run the check if AUTOPROJ_BOOTSTRAP_IGNORE_NONEMPTY_DIR is set" do
                    refute_bootstrap_is_interactive(
                        { "AUTOPROJ_BOOTSTRAP_IGNORE_NONEMPTY_DIR" => "1" },
                        "--seed-config", "seed-config.yml", mode: "bootstrap"
                    )
                end
            end

            def assert_bootstrap_is_interactive(*args, mode:, **kwargs)
                env = [args.shift] if args.first.kind_of?(Hash)
                Bundler.with_unbundled_env do
                    assert_command_is_interactive(
                        *env, Gem.ruby, File.join(@autoproj_bin_dir, "autoproj_#{mode}"),
                        "--gemfile", gemfile_aruba, "--gems-path", @gem_home,
                        *args, **kwargs
                    )
                end
            end

            def refute_bootstrap_is_interactive(*args, mode:, **kwargs)
                env = [args.shift] if args.first.kind_of?(Hash)

                Bundler.with_unbundled_env do
                    refute_command_is_interactive(
                        *env, Gem.ruby, File.join(@autoproj_bin_dir, "autoproj_#{mode}"),
                        "--gemfile", gemfile_aruba, "--gems-path", @gem_home,
                        *args, **kwargs
                    )
                end
            end

            def assert_command_is_interactive(*args, **kwargs)
                r, w = IO.pipe
                pid = Process.spawn(
                    *args, in: :close, out: "/dev/null", err: w,
                           chdir: expand_path("."), **kwargs
                )

                w.close
                output = r.read
                _, status = Process.waitpid2 pid

                assert status.exitstatus != 0,
                       "Command #{args} was expected to fail for lack of standard input "\
                       "but did not\nstderr: #{output}"
                output
            end

            def refute_command_is_interactive(*args, **kwargs)
                r, w = IO.pipe
                pid = Process.spawn(
                    *args, in: :close, out: "/dev/null", err: w,
                           chdir: expand_path("."), **kwargs
                )

                w.close
                output = r.read
                _, status = Process.waitpid2 pid

                assert status.exitstatus == 0,
                       "Command #{args} was expected to finish without error "\
                       "but failed\nstderr: #{output}"
            end
        end
    end
end
