require "autoproj/test"
require "autoproj/aruba_minitest"
require "autoproj/cli/exec"
require "tty-cursor"

module Autoproj
    module CLI
        describe Exec do
            include Autoproj::ArubaMinitest

            before do
                @cursor = TTY::Cursor
                ws_create(expand_path("."))
                set_environment_variable "AUTOPROJ_CURRENT_ROOT", ws.root_dir
                @autoproj_bin =
                    File.expand_path(File.join("..", "..", "bin", "autoproj"), __dir__)

                write_file "subdir/test", <<-STUB_SCRIPT
                    #! /bin/sh
                    echo "ARG $@"
                    echo "ENV $TEST_ENV_VAR"
                STUB_SCRIPT
                chmod 0o755, "subdir/test"
            end

            after do
                FileUtils.chmod_R "a+w", expand_path(".")
                FileUtils.rm_rf expand_path(".")
            end

            describe "without using the cache" do
                before do
                    append_to_file "autoproj/init.rb",
                        "Autoproj.env.set 'TEST_ENV_VAR', 'SOME_VALUE'\n"
                    append_to_file "autoproj/init.rb",
                        "Autoproj.env.add_path 'PATH', '#{expand_path("subdir")}'\n"
                end

                it "resolves the command and execs "\
                   "the process with the internal environment" do
                    cmd = run_command_and_stop "#{@autoproj_bin} exec test --some --arg"
                    assert_equal <<~OUTPUT.chomp, cmd.stdout.chomp
                        ARG --some --arg
                        ENV SOME_VALUE
                    OUTPUT
                end

                it "resolves the command and execs "\
                   "the process with the internal environment" do
                    cmd = run_command_and_stop "#{@autoproj_bin} exec test --some --arg"
                    assert_equal <<~OUTPUT.chomp, cmd.stdout.chomp
                        ARG --some --arg
                        ENV SOME_VALUE
                    OUTPUT
                end

                it "displays an error if the command does not exist" do
                    cmd = run_command_and_stop(
                        "#{@autoproj_bin} exec does_not_exist --some --arg",
                        fail_on_error: false
                    )
                    assert_equal 1, cmd.exit_status
                    assert_equal(
                        "#{@cursor.clear_screen_down}  ERROR: cannot resolve "\
                        "`does_not_exist` to an executable in the workspace\n",
                        cmd.stderr
                    )
                end
            end

            describe "while using the cache" do
                before do
                    path = expand_path("subdir").split(File::PATH_SEPARATOR)
                    cache = Hash[
                        "set" => Hash["PATH" => path, "TEST_ENV_VAR" => ["SOME_VALUE"]],
                        "unset" => Array.new,
                        "update" => Array.new
                    ]
                    write_file ".autoproj/env.yml", YAML.dump(cache)
                end

                it "resolves the command and execs the process "\
                   "with the internal environment" do
                    cmd = run_command_and_stop(
                        "#{@autoproj_bin} exec --use-cache test --some --arg"
                    )
                    assert_equal <<~OUTPUT.chomp, cmd.stdout.chomp
                        ARG --some --arg
                        ENV SOME_VALUE
                    OUTPUT
                end

                it "displays an error if the command does not exist" do
                    cmd = run_command_and_stop(
                        "#{@autoproj_bin} exec --use-cache does_not_exist --some --arg",
                        fail_on_error: false
                    )
                    assert_equal 1, cmd.exit_status
                    assert_equal(
                        "#{@cursor.clear_screen_down}  ERROR: cannot resolve "\
                        "`does_not_exist` to an executable in the workspace\n",
                        cmd.stderr
                    )
                end
            end

            describe "--chdir and --package" do
                before do
                    append_to_file "autoproj/packages.autobuild", <<~INIT
                        import_package "subdir"
                    INIT
                    append_to_file "autoproj/overrides.yml", <<~YML
                        packages:
                            subdir:
                                type: none
                    YML
                end
                it "executes the command in the directory given to --chdir" do
                    dir = make_tmpdir
                    cmd = run_command_and_stop(
                        "#{@autoproj_bin} exec --chdir #{dir} pwd"
                    )
                    assert_equal dir, cmd.stdout.strip
                end

                it "executes the command in the package's source directory "\
                   "when a plain package is given to --package" do
                    cmd = run_command_and_stop(
                        "#{@autoproj_bin} exec --package subdir pwd"
                    )
                    assert_equal expand_path("subdir"), cmd.stdout.strip
                end

                it "executes the command in the package's source directory "\
                   "given to --package" do
                    cmd = run_command_and_stop(
                        "#{@autoproj_bin} exec --package srcdir:subdir pwd"
                    )
                    assert_equal expand_path("subdir"), cmd.stdout.strip
                end

                it "searches for the executable within the --chdir" do
                    cmd = run_command_and_stop(
                        "#{@autoproj_bin} exec --package subdir test --some --arg"
                    )
                    assert_equal <<~OUTPUT.strip, cmd.stdout.strip
                        ARG --some --arg
                        ENV
                    OUTPUT
                end

                it "resolves a relative chdir when --package is also given" do
                    target_dir = expand_path("subdir/bla")
                    FileUtils.mkdir_p target_dir
                    cmd = run_command_and_stop(
                        "#{@autoproj_bin} exec --chdir bla --package srcdir:subdir pwd"
                    )
                    assert_equal target_dir, cmd.stdout.strip
                end

                it "errors if the package has no builddir but a builddir is requested" do
                    cmd = run_command_and_stop(
                        "#{@autoproj_bin} exec --no-color --package builddir:subdir pwd",
                        fail_on_error: false
                    )
                    assert_equal(
                        "#{@cursor.clear_screen_down}  "\
                        "ERROR: package subdir has no builddir",
                        cmd.stderr.strip
                    )
                end
            end

            describe "in a read-only workspace" do
                before do
                    append_to_file "autoproj/packages.autobuild", <<~INIT
                        import_package "subdir"
                    INIT
                    append_to_file "autoproj/overrides.yml", <<~YML
                        packages:
                            subdir:
                                type: none
                    YML
                end

                it "runs normally" do
                    FileUtils.chmod_R "a-w", expand_path(".")
                    dir = make_tmpdir
                    cmd = run_command_and_stop(
                        "#{@autoproj_bin} exec --package subdir test --some --arg"
                    )
                    assert_equal <<~OUTPUT.strip, cmd.stdout.strip
                        ARG --some --arg
                        ENV
                    OUTPUT
                end
            end
        end
    end
end
