require 'autoproj/test'
require 'autoproj/cli/main'
require 'autoproj/cli/status'

module Autoproj
    module CLI
        describe Status do
            attr_reader :cli
            before do
                ws_create
                @cli = Status.new(ws)
            end

            describe "-n" do
                it "turns dependencies off" do
                    flexmock(Status).new_instances.
                        should_receive(:run).with([], hsh(deps: false)).once
                    in_ws do
                        Main.start(['status', '-n'])
                    end
                end
            end
        end
    end
end

