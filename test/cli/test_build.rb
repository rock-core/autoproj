require "autoproj/test"
require "autoproj/cli/main"
require "autoproj/cli/build"

module Autoproj
    module CLI
        describe Build do
            attr_reader :cli

            before do
                ws_create
                @cli = Build.new(ws)
                Autoproj.silent = true
            end

            after do
                Autoproj.silent = false
            end

            describe "the main CLI" do
                describe "-n" do
                    it "turns dependencies off" do
                        flexmock(Update).new_instances
                                        .should_receive(:run).with([])
                                        .with_kw_args(hsh(deps: false)).once
                        in_ws do
                            Main.start(["build", "-n", "--silent"])
                        end
                    end
                end

                it "fails with the actual error if the manifest cannot be "\
                   "resolved due to a configuration error" do
                    # This is a regression test. `autoproj build` would fail
                    # during env.sh generation if the load failed, in case
                    # the layout could not be resolved
                    dir = make_tmpdir
                    File.open(ws.manifest_file_path, "w") do |io|
                        manifest_data = {
                            "package_sets" => [dir],
                            "layout" => ["some"]
                        }
                        YAML.dump(manifest_data, io)
                    end
                    e = assert_raises(Autoproj::ConfigError) do
                        @cli.run([], silent: true)
                    end
                    assert_equal "package set local:#{dir} present in #{dir} should "\
                                 "have a source.yml file, but does not", e.message
                end
            end

            describe "#validate_options" do
                it "normalizes the selection" do
                    flexmock(cli).should_receive(:normalize_command_line_package_selection)
                                 .with(selection = flexmock(empty?: false))
                                 .and_return([normalized_selection = flexmock(empty?: false),
                                              false])

                    selection, _options = cli.validate_options(selection, Hash.new)
                    assert_equal normalized_selection, selection
                end

                describe "the amake mode" do
                    it "sets the selection to the current directory" do
                        selection, = cli.validate_options([], amake: true)
                        assert_equal ["#{Dir.pwd}/"], selection
                    end
                    it "leaves an explicit selection alone" do
                        selection, = cli.validate_options(["/a/path"], amake: true)
                        assert_equal ["/a/path"], selection
                    end
                    it "leaves an empty selection alone if --all is given" do
                        selection, = cli.validate_options([], amake: true, all: true)
                        assert_equal [], selection
                    end
                    it "sets the 'all' flag automatically if given no explicit arguments and the working directory is the workspace's root" do
                        Dir.chdir(ws.root_dir) do
                            _, options = cli.validate_options([], amake: true)
                            assert options[:all]
                        end
                    end
                    it "does not set the 'all' flag automatically if given explicit arguments even if the working directory is the workspace's root" do
                        Dir.chdir(ws.root_dir) do
                            _, options = cli.validate_options(["arg"], amake: true)
                            refute options[:all]
                        end
                    end
                end
            end
        end
    end
end
