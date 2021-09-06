require "autoproj/test"
require "autoproj/cli/clean"

module Autoproj
    module CLI
        describe Clean do
            attr_reader :cli
            before do
                ws_create
                @cli = Clean.new(ws)
                flexmock(cli)
                # bypass initialize_and_load since we do our own mock
                # configuration
                cli.should_receive(:initialize_and_load)
            end

            describe "#validate_options" do
                describe "confirmation if no packages have been selected" do
                    it "passes if the user replied 'yes'" do
                        flexmock(TTY::Prompt).new_instances.
                            should_receive(:yes?).and_return(true)
                        assert_equal [[], Hash.new], cli.validate_options([], Hash.new)
                    end
                    it "raises if the user replied 'yes'" do
                        flexmock(TTY::Prompt).new_instances.
                            should_receive(:yes?).and_return(false)
                        assert_raises(Interrupt) do
                            cli.validate_options([], Hash.new)
                        end
                    end
                    it "does not ask confirmation if the 'all' options is true" do
                        flexmock(TTY::Prompt).new_instances.
                            should_receive(:yes?).never
                        assert_equal [[], Hash[all: true]], cli.validate_options([], all: true)
                    end
                end
            end

            it "cleans recursively if no packages have been given on the command line" do
                pkg0 = ws_add_package_to_layout :cmake, "package"
                pkg1 = ws_define_package :cmake, "other"
                pkg0.depends_on pkg1
                flexmock(pkg0.autobuild).should_receive(:prepare_for_rebuild).once
                flexmock(pkg1.autobuild).should_receive(:prepare_for_rebuild).once
                cli.run([])
            end

            it "cleans only explicitely selected packages if no packages have been given on the command line and :deps is false" do
                pkg0 = ws_add_package_to_layout :cmake, "package"
                pkg1 = ws_define_package :cmake, "other"
                pkg0.depends_on pkg1
                flexmock(pkg0.autobuild).should_receive(:prepare_for_rebuild).once
                flexmock(pkg1.autobuild).should_receive(:prepare_for_rebuild).never
                cli.run([], deps: false)
            end

            it "cleans only explicitely given packages by default" do
                pkg0 = ws_add_package_to_layout :cmake, "package"
                pkg1 = ws_define_package :cmake, "other"
                pkg0.depends_on pkg1
                flexmock(pkg0.autobuild).should_receive(:prepare_for_rebuild).once
                flexmock(pkg1.autobuild).should_receive(:prepare_for_rebuild).never
                cli.run(["package"])
            end

            it "cleans explicitely given packages and their dependency if :deps is set" do
                pkg0 = ws_add_package_to_layout :cmake, "package"
                pkg1 = ws_define_package :cmake, "other"
                pkg0.depends_on pkg1
                flexmock(pkg0.autobuild).should_receive(:prepare_for_rebuild).once
                flexmock(pkg1.autobuild).should_receive(:prepare_for_rebuild).once
                cli.run(["package"], deps: true)
            end
        end
    end
end
