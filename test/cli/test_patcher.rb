require "autoproj/test"
require "autoproj/cli/patcher"

module Autoproj
    module CLI
        describe Patcher do
            attr_reader :cli, :package

            before do
                ws_create
                @cli = Patcher.new(ws)
                flexmock(ws.os_package_installer).should_receive(:install)
                flexmock(cli).should_receive(:initialize_and_load)

                @package = ws_define_package :cmake, "base/cmake"
                package.vcs = VCSDefinition.from_raw(type: "git", url: "/test")
                package.autobuild.srcdir = File.join(ws.root_dir, "package")
                FileUtils.mkdir_p(package.autobuild.srcdir)
                package.autobuild.importer = package.vcs.create_autobuild_importer
                # This looks as ugly as it actually is. I'm trying to get
                # autoproj v2 out of the door, and already did a lot of work to
                # clean it up in the last weeks ... this one stays this time
                flexmock(package.autobuild.importer)
                    .should_receive(:patches)
                    .and_return([["/path/to/patch", 1, ""]])

                Autobuild.silent = true
            end

            describe "patch: true" do
                it "applies the necessary patches" do
                    flexmock(package.autobuild.importer)
                        .should_receive(:apply)
                        .with(package.autobuild, "/path/to/patch", 1).once
                    cli.run(["base/cmake"], patch: true)
                end
            end

            describe "patch: false" do
                it "removes the patches" do
                    flexmock(package.autobuild.importer)
                        .should_receive(:apply)
                        .globally.ordered
                    patch_file = File.join(package.autobuild.importer.patchdir(package.autobuild), "0")
                    flexmock(package.autobuild.importer)
                        .should_receive(:unapply)
                        .with(package.autobuild, patch_file, 1).once
                        .globally.ordered
                    cli.run(["base/cmake"], patch: true)
                    cli.run(["base/cmake"], patch: false)
                end
            end
        end
    end
end
