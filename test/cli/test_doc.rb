require "autoproj/test"
require "autoproj/cli/main"
require "autoproj/cli/doc"

module Autoproj
    module CLI
        describe Doc do
            attr_reader :cli

            before do
                ws_create
                @one = ws_add_package_to_layout :cmake, "one"
                @cli = Doc.new(ws)
                flexmock(cli)
            end

            describe "#run" do
                it "executes utility's task" do
                    flexmock(@one.autobuild.doc_utility).should_receive(:install).once
                    a = @one.autobuild.doc_utility
                    a.task {}
                    cli.run(%w[one])
                    assert a.invoked?
                end
            end

            %w[enable disable list exec].each do |subcommand|
                describe "--deps" do
                    it "turns dependencies on" do
                        meth = subcommand
                        meth = "run" if subcommand == "exec"

                        flexmock(Doc).new_instances
                                     .should_receive(meth.to_sym)
                                     .with(%w[pkg1 pkg2])
                                     .with_kw_args(hsh(deps: true))
                                     .once
                        in_ws do
                            Main.start(["doc", subcommand, "--deps", "pkg1", "pkg2"])
                        end
                    end
                end
            end

            describe "-n" do
                it "turns dependencies off" do
                    flexmock(Doc).new_instances
                                 .should_receive(:run)
                                 .with(%w[pkg1 pkg2])
                                 .with_kw_args(hsh(deps: false))
                                 .once
                    in_ws do
                        Main.start(["doc", "-n", "pkg1", "pkg2"])
                    end
                end
            end
        end
    end
end
