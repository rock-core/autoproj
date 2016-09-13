require 'autoproj/test'
require 'autoproj/cli/manifest'

module Autoproj
    module CLI
        describe Manifest do
            attr_reader :cli
            before do
                ws_create
                @cli = Manifest.new(ws)
            end

            def assert_configured_manifest(expected_name, expected_full_path)
                ws = Workspace.new(self.ws.root_dir)
                ws.load_config
                assert_equal expected_name, ws.config.get('manifest_name', 'manifest')
                assert_equal expected_full_path, ws.manifest_file_path
            end

            it "displays the current manifest if given no arguments" do
                flexmock(ws).should_receive(:manifest_file_path).
                    and_return("test.manifest")
                flexmock(Autoproj).should_receive(:message).
                    with("current manifest is test.manifest").
                    once
                cli.run([])
            end
            it "raises if given more than one argument" do
                e = assert_raises(ArgumentError) do
                    cli.run(['a', 'b'])
                end
                assert_equal "expected zero or one argument, but got 2", e.message
            end

            it "resolves a path to a manifest" do
                full_path = File.join(ws.config_dir, 'test.manifest')
                FileUtils.touch full_path
                Dir.chdir(ws.root_dir) do
                    flexmock(Autoproj).should_receive(:message).once.
                        with("set manifest to #{full_path}")
                    cli.run([File.join('autoproj/test.manifest')])
                end
                assert_configured_manifest 'test.manifest', full_path
            end

            it "resolves a file name within the config dir" do
                full_path = File.join(ws.config_dir, 'test.manifest')
                FileUtils.touch full_path
                flexmock(Autoproj).should_receive(:message).once.
                    with("set manifest to #{full_path}")
                cli.run(['test.manifest'])
                assert_configured_manifest 'test.manifest', full_path
            end

            it "allows to specify only the extension to 'manifest'" do
                full_path = File.join(ws.config_dir, 'manifest.test')
                FileUtils.touch full_path
                flexmock(Autoproj).should_receive(:message).once.
                    with("set manifest to #{full_path}")
                cli.run(['test'])
                assert_configured_manifest 'manifest.test', full_path
            end

            it "raises if the file does not exist" do
                full_path = File.join(ws.config_dir, 'test')
                alternative_full_path = File.join(ws.config_dir, 'manifest.test')
                e = assert_raises(ArgumentError) do
                    cli.run(['test'])
                end
                assert_equal "neither #{full_path} nor #{alternative_full_path} exist",
                    e.message
            end

            it "validates that the resulting file can be loaded as a manifest" do
                full_path = File.join(ws.config_dir, 'manifest.test')
                File.open(full_path, 'w') do |io|
                    io.puts "invalid\nyaml:"
                end
                flexmock(Autoproj).should_receive(:error).once.
                    with("failed to load #{full_path}")
                assert_raises(ConfigError) do
                    cli.run(['test'])
                end
                assert_configured_manifest 'manifest', File.join(ws.config_dir, 'manifest')
            end

            it "raises if the path to the manifest is outside the workspace config dir" do
                full_path = File.join(ws.root_dir, 'test.manifest')
                FileUtils.touch full_path
                e = assert_raises(ArgumentError) do
                    cli.run([full_path])
                end
                assert_equal "#{full_path} is not part of #{ws.config_dir}",
                    e.message
                assert_configured_manifest 'manifest', File.join(ws.config_dir, 'manifest')
            end
        end
    end
end

