require "autoproj/test"
require "autoproj/aruba_minitest"

module Autoproj
    module CLI
        describe "bootstrap" do
            include ArubaMinitest

            before do
                @autoproj_bin_dir = File.expand_path(
                    File.join("..", "..", "bin"), __dir__)
            end

            describe "interactivity" do
                it "is interactive by default" do
                    output = assert_command_is_interactive("#{Gem.ruby} "\
                        "#{File.join(@autoproj_bin_dir, 'autoproj_install')} "\
                        "--gemfile '#{gemfile_aruba}'")
                    assert_match(/build_option.rb:.*:in `readline': end of file reached/,
                        output)
                end

                it "is not interactive if --no-interactive is given on the command line" do
                    refute_command_is_interactive("#{Gem.ruby} "\
                        "#{File.join(@autoproj_bin_dir, 'autoproj_install')} "\
                        "--gemfile '#{gemfile_aruba}' --no-interactive")
                end

                it "is not interactive if AUTOPROJ_NONINTERACTIVE is set" do
                    refute_command_is_interactive({ "AUTOPROJ_NONINTERACTIVE" => "1" },
                        "#{Gem.ruby} "\
                        "#{File.join(@autoproj_bin_dir, 'autoproj_install')} "\
                        "--gemfile '#{gemfile_aruba}'")
                end
            end

            describe "empty dir check" do
                before do
                    FileUtils.touch expand_path("some_file")
                    # Need to feed some seed config so that we don't fail
                    # on config questions as opposed to the non-empty check
                    File.open(expand_path("seed-config.yml"), "w") do |io|
                        YAML.dump({
                            "osdeps_mode" => "all",
                            "apt_dpkg_update" => true
                        }, io)
                    end
                end

                it "is tests by default that the install dir is empty" do
                    output = assert_command_is_interactive("#{Gem.ruby} "\
                        "#{File.join(@autoproj_bin_dir, 'autoproj_bootstrap')} "\
                        "--gemfile '#{gemfile_aruba}' --seed-config 'seed-config.yml'")
                    assert_match(/check_root_dir_empty/, output)
                end

                it "does not run the check if --no-interactive is given" do
                    refute_command_is_interactive("#{Gem.ruby} "\
                        "#{File.join(@autoproj_bin_dir, 'autoproj_bootstrap')} "\
                        "--gemfile '#{gemfile_aruba}' --no-interactive")
                end

                it "does not run the check if AUTOPROJ_NONINTERACTIVE is set" do
                    refute_command_is_interactive({ "AUTOPROJ_NONINTERACTIVE" => "1" },
                        "#{Gem.ruby} "\
                        "#{File.join(@autoproj_bin_dir, 'autoproj_bootstrap')} "\
                        "--gemfile '#{gemfile_aruba}'")
                end

                it "does not run the check if AUTOPROJ_BOOTSTRAP_IGNORE_NONEMPTY_DIR is set" do
                    output = assert_command_is_interactive(
                        { "AUTOPROJ_BOOTSTRAP_IGNORE_NONEMPTY_DIR" => "1" },
                        "#{Gem.ruby} "\
                        "#{File.join(@autoproj_bin_dir, 'autoproj_bootstrap')} "\
                        "--gemfile '#{gemfile_aruba}'")
                    assert_match(/build_option.rb:.*:in `readline': end of file reached/,
                        output)
                end
            end

            def assert_command_is_interactive(*args, **kwargs)
                r, w = IO.pipe
                pid = Process.spawn(*args,
                    in: :close, out: "/dev/null", err: w,
                    chdir: expand_path("."), **kwargs)

                w.close
                output = r.read
                _, status = Process.waitpid2 pid

                assert status.exitstatus != 0, "stderr: #{output}"
                output
            end

            def refute_command_is_interactive(*args, **kwargs)
                r, w = IO.pipe
                pid = Process.spawn(*args,
                    in: :close, out: "/dev/null", err: w,
                    chdir: expand_path("."), **kwargs)

                w.close
                output = r.read
                _, status = Process.waitpid2 pid

                assert status.exitstatus == 0, "stderr: #{output}"
            end
        end
    end
end
