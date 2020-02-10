require 'autoproj/test'
require 'autoproj/aruba_minitest'
require 'autoproj/cli/which'
require 'tty-cursor'

module Autoproj
    module CLI
        describe Which do
            include Autoproj::ArubaMinitest
            before do
                @cursor = TTY::Cursor
                ws_create(expand_path('.'))
                set_environment_variable 'AUTOPROJ_CURRENT_ROOT', ws.root_dir
                @autoproj_bin = File.expand_path(File.join("..", "..", "bin", "autoproj"), __dir__)
            end

            describe "without using the cache" do
                it "resolves an executable that can be found in autoproj's PATH" do
                    write_file 'subdir/test', ''
                    chmod 0755, 'subdir/test'
                    append_to_file 'autoproj/init.rb',
                        "Autoproj.env.add_path 'PATH', '#{expand_path('subdir')}'"

                    cmd = run_command_and_stop "#{@autoproj_bin} which test"
                    assert_equal expand_path('subdir/test'), cmd.stdout.chomp
                end

                it "raises if the executable cannot be resolved" do
                    cmd = run_command_and_stop "#{@autoproj_bin} which does_not_exist", fail_on_error: false
                    assert_equal 1, cmd.exit_status
                    assert_equal "#{@cursor.clear_screen_down}  ERROR: cannot resolve `does_not_exist` to an executable in the workspace\n", cmd.stderr
                end
            end

            describe "using the cache" do
                it "uses the cache to resolve the executable" do
                    path = expand_path('subdir').split(File::PATH_SEPARATOR)
                    cache = Hash[
                        'set' => Hash['PATH' => path],
                        'unset' => Array.new,
                        'update' => Array.new
                    ]
                    write_file '.autoproj/env.yml', YAML.dump(cache)

                    write_file 'subdir/test', ''
                    chmod 0755, 'subdir/test'
                    cmd = run_command_and_stop "#{@autoproj_bin} which --use-cache test"
                    assert_equal expand_path('subdir/test'), cmd.stdout.chomp
                end
                it "produces an error if the executable cannot be found" do
                    path = expand_path('subdir').split(File::PATH_SEPARATOR)
                    cache = Hash[
                        'set' => Hash['PATH' => path],
                        'unset' => Array.new,
                        'update' => Array.new
                    ]
                    write_file '.autoproj/env.yml', YAML.dump(cache)
                    cmd = run_command_and_stop "#{@autoproj_bin} which --use-cache does_not_exist", fail_on_error: false
                    assert_equal 1, cmd.exit_status
                    assert_equal "#{@cursor.clear_screen_down}  ERROR: cannot resolve `does_not_exist` to an executable in the workspace\n", cmd.stderr
                end
            end
        end
    end
end

