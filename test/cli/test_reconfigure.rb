require 'autoproj/test'
require 'autoproj/cli/main'
require 'autoproj/cli/reconfigure'
require 'timeout'

module Autoproj
    module CLI
        describe Reconfigure do
            attr_reader :ws
            before do
                option_name = "custom-configuration-option"
                default_value = "option-defaultvalue"

                @ws = ws_create(make_tmpdir, partial_config: true)
            end
            after do
                Autoproj.verbose = false
            end
            describe "#reconfigure" do
                def run_command(*args)
                    capture_subprocess_io do
                        ENV['AUTOPROJ_CURRENT_ROOT'] = ws.root_path.to_s
                        in_ws do
                            Main.start([*args,"--debug"], debug: true)
                        end
                    end
                end

                it "reconfigure should run interactively" do
                    assert_raises Timeout::Error do
                        Timeout.timeout(3) do
                            run_command 'reconfigure'
                        end
                    end
                end
                it "reconfigure should run non interactively" do
                    run_command 'reconfigure','--no-interactive'
                end
            end
        end
    end
end
