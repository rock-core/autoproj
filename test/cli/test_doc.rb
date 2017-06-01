require 'autoproj/test'
require 'autoproj/cli/main'
require 'autoproj/cli/doc'

module Autoproj
    module CLI
        describe Doc do
            attr_reader :cli
            before do
                ws_create
                @cli = Doc.new(ws)
            end

            describe "-n" do
                it "turns dependencies off" do
                    flexmock(Doc).new_instances.
                        should_receive(:run).with([], hsh(deps: false)).once
                    in_ws do
                        Main.start(['doc', '-n'])
                    end
                end
            end
        end
    end
end


