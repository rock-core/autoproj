require 'autoproj/test'
require 'autoproj/aruba_minitest'
require 'autoproj/cli/exec'
require 'tty-cursor'

module Autoproj
    module CLI
        describe Exec do
            include Autoproj::ArubaMinitest
            before do
                @cursor = TTY::Cursor
                ws_create(expand_path('.'))
                set_environment_variable 'AUTOPROJ_CURRENT_ROOT', ws.root_dir
                @autoproj_bin = File.expand_path(File.join("..", "..", "bin", "autoproj"), __dir__)

                write_file 'subdir/test', <<-STUB_SCRIPT
                    #! /bin/sh
                    echo "ARG $@"
                    echo "ENV $TEST_ENV_VAR"
                STUB_SCRIPT
                chmod 0o755, 'subdir/test'
            end

            describe "without using the cache" do
                before do
                    append_to_file 'autoproj/init.rb',
                        "Autoproj.env.set 'TEST_ENV_VAR', 'SOME_VALUE'\n"
                    append_to_file 'autoproj/init.rb',
                        "Autoproj.env.add_path 'PATH', '#{expand_path('subdir')}'\n"
                end

                it "resolves the command and execs the process with the internal environment" do
                    cmd = run_command_and_stop "#{@autoproj_bin} exec test --some --arg"
                    assert_equal <<-OUTPUT.chomp, cmd.stdout.chomp
ARG --some --arg
ENV SOME_VALUE
                    OUTPUT
                end

                it "displays an error if the command does not exist" do
                    cmd = run_command_and_stop "#{@autoproj_bin} exec does_not_exist --some --arg",
                        fail_on_error: false
                    assert_equal 1, cmd.exit_status
                    assert_equal "#{@cursor.clear_screen_down}  ERROR: cannot resolve `does_not_exist` to an executable in the workspace\n",
                        cmd.stderr
                end
            end

            describe "while using the cache" do
                before do
                    path = expand_path('subdir').split(File::PATH_SEPARATOR)
                    cache = Hash[
                        'set' => Hash['PATH' => path, 'TEST_ENV_VAR' => ['SOME_VALUE']],
                        'unset' => Array.new,
                        'update' => Array.new
                    ]
                    write_file '.autoproj/env.yml', YAML.dump(cache)
                end

                it "resolves the command and execs the process with the internal environment" do
                    cmd = run_command_and_stop "#{@autoproj_bin} exec --use-cache test --some --arg"
                    assert_equal <<-OUTPUT.chomp, cmd.stdout.chomp
ARG --some --arg
ENV SOME_VALUE
                    OUTPUT
                end

                it "displays an error if the command does not exist" do
                    cmd = run_command_and_stop "#{@autoproj_bin} exec --use-cache does_not_exist --some --arg",
                        fail_on_error: false
                    assert_equal 1, cmd.exit_status
                    assert_equal "#{@cursor.clear_screen_down}  ERROR: cannot resolve `does_not_exist` to an executable in the workspace\n",
                        cmd.stderr
                end
            end
        end
    end
end

#module Autoproj
#    module CLI
#        describe Exec do
#            before do
#                ws_create
#                @cli = Exec.new(ws)
#                flexmock(@cli).should_receive(:initialize_and_load)
#            end
#
#            it "passes the full environment, program and the arguments to the exec'd process" do
#                flexmock(ws).should_receive(:which).with("path").
#                    and_return('/resolved/path')
#                env = flexmock
#                flexmock(ws).should_receive(:full_env => flexmock(resolved_env: env))
#                flexmock(Process).should_receive(:exec).with(env, "/resolved/path", 'args').once
#                @cli.run('path', 'args')
#            end
#
#            it "re-raises any exception raised by Process as a CLIInvalidArguments" do
#                flexmock(ws).should_receive(:which).with("path").
#                    and_return('/resolved/path')
#                flexmock(Process).should_receive(:exec).
#                    and_raise(RuntimeError.new("ENOENT"))
#                e = assert_raises(CLIInvalidArguments) do
#                    @cli.run('path')
#                end
#                assert_equal "ENOENT", e.message
#            end
#
#            it "re-raises a ExecutableNotFound originally raised by Workspace#which" do
#                flexmock(ws).should_receive(:which).with("path").
#                    and_raise(Workspace::ExecutableNotFound.new("cannot find"))
#                e = assert_raises(CLIInvalidArguments) do
#                    @cli.run('path')
#                end
#                assert_equal "cannot find", e.message
#            end
#        end
#    end
#end
#
#
#
