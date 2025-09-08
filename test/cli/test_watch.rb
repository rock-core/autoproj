require "autoproj/test"
require "autoproj/cli/watch"

module Autoproj
    module CLI
        describe Watch do
            attr_reader :cli
            attr_reader :ws

            before do
                @ws = ws_create
                @cli = Watch.new(ws)
                flexmock(cli)
                cli.should_receive(:puts).explicitly
            end

            describe "#update_workspace" do
                it "loads the workspace and updates env.sh" do
                    cli.should_receive(:initialize_and_load).once.ordered
                    cli.should_receive(:finalize_setup).once.ordered.and_return([[], nil])
                    cli.should_receive(:export_env_sh).once.ordered

                    cli.update_workspace
                end
            end

            describe "#callback" do
                it "stops the notifier runloop" do
                    cli.setup_notifier
                    flexmock(cli.notifier)
                    cli.notifier.should_receive(:stop).once
                    cli.callback.join
                end
            end

            describe "#start_watchers" do
                attr_reader :pkg
                attr_reader :manifest_file
                attr_reader :ros_manifest_file
                attr_reader :pkg_set
                attr_reader :autobuild_file
                attr_reader :ruby_file
                attr_reader :pkg_set_manifest_file
                attr_reader :pkg_set_manifest_dir

                before do
                    ws.config.save
                    @pkg = ws_add_package_to_layout :cmake, "package"
                    @pkg_set = ws.manifest.main_package_set
                    @ros_manifest_file = File.join(pkg.autobuild.srcdir,
                                                   "package.xml")
                    @manifest_file = File.join(pkg.autobuild.srcdir,
                                               "manifest.xml")
                    @autobuild_file = File.join(pkg_set.raw_local_dir,
                                                "packages.autobuild")
                    @ruby_file = File.join(pkg_set.raw_local_dir,
                                           "file.rb")
                    @pkg_set_manifest_dir = File.join(pkg_set.raw_local_dir,
                                                      "manifests")
                    @pkg_set_manifest_file = File.join(pkg_set_manifest_dir,
                                                       "tools", "package.xml")

                    File.write(manifest_file, "<package />")
                    File.write(ros_manifest_file, "<package />")
                    FileUtils.touch(autobuild_file)
                    FileUtils.touch(ruby_file)
                    FileUtils.mkdir_p(File.join(pkg_set_manifest_dir, "tools"))
                    File.write(pkg_set_manifest_file, "<package />")
                    sleep 0.1
                    cli.update_workspace
                    cli.setup_notifier
                    cli.start_watchers
                end
                after do
                    cli.cleanup_notifier if cli.notifier
                end

                def process_events
                    sleep 0.1
                    cli.notifier.process if cli.notifier.to_io.wait_readable(1)
                end
                describe "main configuration watcher" do
                    it "triggers the callback when the file is modified" do
                        cli.should_receive(:callback).once
                        File.open(ws.config.path, "a") do |file|
                            file << "\n"
                        end
                        process_events
                    end
                    it "triggers the callback when the file is deleted" do
                        cli.should_receive(:callback).once
                        File.unlink(ws.config.path)
                        process_events
                    end
                    it "triggers the callback when the file is overwritten" do
                        cli.should_receive(:callback).once
                        config_copy = File.join(ws.root_dir, "config.yml.orig")
                        FileUtils.cp(ws.config.path, config_copy)
                        FileUtils.mv(config_copy, ws.config.path)
                        process_events
                    end
                end
                describe "main manifest watcher" do
                    it "triggers the callback when the file is modified" do
                        cli.should_receive(:callback).once
                        File.open(ws.manifest_file_path, "a") do |file|
                            file << "\n"
                        end
                        process_events
                    end
                    it "triggers the callback when the file is deleted" do
                        cli.should_receive(:callback).once
                        File.unlink(ws.manifest_file_path)
                        process_events
                    end
                    it "triggers the callback when the file is overwritten" do
                        cli.should_receive(:callback).once
                        manifest_copy = File.join(ws.root_dir, "manifest.orig")
                        FileUtils.cp(ws.manifest_file_path, manifest_copy)
                        FileUtils.mv(manifest_copy, ws.manifest_file_path)
                        process_events
                    end
                end
                describe "in-source manifest watcher" do
                    it "triggers the callback when the file is created" do
                        # The callback stops the watcher ... make it a no-op
                        def cli.callback; end
                        File.unlink(manifest_file)
                        process_events
                        cli.should_receive(:callback).once
                        FileUtils.touch(manifest_file)
                        process_events
                    end
                    it "triggers the callback when the file is modified" do
                        cli.should_receive(:callback).at_least.once
                        File.open(manifest_file, "a") do |file|
                            file << "\n"
                        end
                        process_events
                    end
                    it "triggers the callback when the file is deleted" do
                        cli.should_receive(:callback).at_least.once
                        File.unlink(manifest_file)
                        process_events
                    end
                    it "triggers the callback when the file is overwritten" do
                        cli.should_receive(:callback).at_least.once
                        manifest_copy = File.join(ws.root_dir, "manifest.xml")
                        FileUtils.cp(manifest_file, manifest_copy)
                        FileUtils.mv(manifest_copy, manifest_file)
                        process_events
                    end
                end
                describe "in-source ROS manifest watcher" do
                    it "triggers the callback when the file is created" do
                        # The callback stops the watcher ... make it a no-op
                        def cli.callback; end
                        File.unlink(ros_manifest_file)
                        process_events
                        cli.should_receive(:callback).once
                        FileUtils.touch(ros_manifest_file)
                        process_events
                    end
                    it "triggers the callback when the file is modified" do
                        cli.should_receive(:callback).at_least.once
                        File.open(ros_manifest_file, "a") do |file|
                            file << "\n"
                        end
                        process_events
                    end
                    it "triggers the callback when the file is deleted" do
                        cli.should_receive(:callback).at_least.once
                        File.unlink(ros_manifest_file)
                        process_events
                    end
                    it "triggers the callback when the file is overwritten" do
                        cli.should_receive(:callback).at_least.once
                        manifest_copy = File.join(ws.root_dir, "package.xml")
                        FileUtils.cp(ros_manifest_file, manifest_copy)
                        FileUtils.mv(manifest_copy, ros_manifest_file)
                        process_events
                    end
                end
                describe "autobuild package definitions watcher" do
                    it "triggers the callback when an autobuild file is created" do
                        cli.should_receive(:callback).once
                        FileUtils.touch(File.join(pkg_set.raw_local_dir, "test.autobuild"))
                        process_events
                    end
                    it "triggers the callback when an autobuild file is modified" do
                        cli.should_receive(:callback).once
                        File.open(autobuild_file, "a") do |file|
                            file << "\n"
                        end
                        process_events
                    end
                    it "triggers the callback when an autobuild file is deleted" do
                        cli.should_receive(:callback).at_least.once
                        File.unlink(autobuild_file)
                        process_events
                    end
                    it "triggers the callback when a autobuild file is overwritten" do
                        cli.should_receive(:callback).at_least.once
                        autobuild_copy = File.join(ws.root_dir, "packages.autobuild")
                        FileUtils.cp(autobuild_file, autobuild_copy)
                        FileUtils.mv(autobuild_copy, autobuild_file)
                        process_events
                    end
                end
                describe "ruby files watcher" do
                    it "triggers the callback when a ruby file is created" do
                        cli.should_receive(:callback).once
                        FileUtils.touch(File.join(pkg_set.raw_local_dir, "test.rb"))
                        process_events
                    end
                    it "triggers the callback when a ruby file is modified" do
                        cli.should_receive(:callback).once
                        File.open(ruby_file, "a") do |file|
                            file << "\n"
                        end
                        process_events
                    end
                    it "triggers the callback when a ruby file is deleted" do
                        cli.should_receive(:callback).at_least.once
                        File.unlink(ruby_file)
                        process_events
                    end
                    it "triggers the callback when a ruby file is overwritten" do
                        cli.should_receive(:callback).at_least.once
                        ruby_copy = File.join(ws.root_dir, "file.rb")
                        FileUtils.cp(ruby_file, ruby_copy)
                        FileUtils.mv(ruby_copy, ruby_file)
                        process_events
                    end
                end
                describe "in-pkg set manifest files watcher" do
                    it "triggers the callback when a manifest file is modified" do
                        cli.should_receive(:callback).once
                        File.open(pkg_set_manifest_file, "a") do |file|
                            file << "\n"
                        end
                        process_events
                    end
                    it "triggers the callback when a manifest file is deleted" do
                        cli.should_receive(:callback).at_least.once
                        File.unlink(pkg_set_manifest_file)
                        process_events
                    end
                    it "triggers the callback when a manifest file is overwritten" do
                        cli.should_receive(:callback).at_least.once
                        manifest_copy = File.join(ws.root_dir, "package.xml")
                        FileUtils.cp(pkg_set_manifest_file, manifest_copy)
                        FileUtils.mv(manifest_copy, pkg_set_manifest_file)
                        process_events
                    end
                end
            end
        end
    end
end
