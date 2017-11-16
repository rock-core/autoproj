require 'autoproj/test'
require 'autoproj/cli/main'
require 'autoproj/cli/build'

module Autoproj
    module CLI
        describe Build do
            attr_reader :cli
            before do
                ws_create
                @cli = Build.new(ws)
            end

            describe "the main CLI" do
                describe "-n" do
                    it "turns dependencies off" do
                        flexmock(Update).new_instances.
                            should_receive(:run).with([], hsh(deps: false)).once
                        in_ws do
                            Main.start(['build', '-n', '--silent'])
                        end
                    end
                end
            end

            describe "#validate_options" do
                it "normalizes the selection" do
                    flexmock(cli).should_receive(:normalize_command_line_package_selection).
                        with(selection = flexmock(:empty? => false)).
                        and_return([normalized_selection = flexmock(:empty? => false),
                                    false])

                    selection, _options = cli.validate_options(selection, Hash.new)
                    assert_equal normalized_selection, selection
                end

                describe "the amake mode" do
                    it "sets the selection to the current directory" do
                        selection, _ = cli.validate_options([], amake: true)
                        assert_equal ["#{Dir.pwd}/"], selection
                    end
                    it "leaves an explicit selection alone" do
                        selection, _ = cli.validate_options(['/a/path'], amake: true)
                        assert_equal ['/a/path'], selection
                    end
                    it "leaves an empty selection alone if --all is given" do
                        selection, _ = cli.validate_options([], amake: true, all: true)
                        assert_equal [], selection
                    end
                    it "sets the 'all' flag automatically if given no explicit arguments and the working directory is the workspace's root" do
                        Dir.chdir(ws.root_dir) do
                            args, options = cli.validate_options([], amake: true)
                            assert options[:all]
                        end
                    end
                    it "does not set the 'all' flag automatically if given explicit arguments even if the working directory is the workspace's root" do
                        Dir.chdir(ws.root_dir) do
                            args, options = cli.validate_options(['arg'], amake: true)
                            refute options[:all]
                        end
                    end
                end
            end
        end
    end
end



