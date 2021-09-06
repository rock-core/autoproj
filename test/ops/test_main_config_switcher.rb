require "autoproj/test"
require "autoproj/ops/main_config_switcher"

module Autoproj
    module Ops
        describe MainConfigSwitcher do
            before do
                @ws = ws_create
                @ops = MainConfigSwitcher.new(@ws)
            end

            describe "#check_root_dir_empty?" do
                after do
                    ENV.delete("AUTOPROJ_NONINTERACTIVE")
                    ENV.delete("AUTOPROJ_BOOTSTRAP_IGNORE_NONEMPTY_DIR")
                end

                it "is enabled by default" do
                    assert @ops.check_root_dir_empty?
                end

                it "is disabled if AUTOPROJ_NONINTERACTIVE is set to 1" do
                    ENV["AUTOPROJ_NONINTERACTIVE"] = "1"
                    refute @ops.check_root_dir_empty?
                end

                it "is disabled if AUTOPROJ_BOOTSTRAP_IGNORE_NONEMPTY_DIR is set to 1" do
                    ENV["AUTOPROJ_BOOTSTRAP_IGNORE_NONEMPTY_DIR"] = "1"
                    refute @ops.check_root_dir_empty?
                end
            end

            describe "#bootstrap" do
                it "calls check_root_dir_empty by default" do
                    flexmock(@ops).should_receive(:check_root_dir_empty)
                                  .and_throw(:bypass)
                    assert_throws(:bypass) { @ops.bootstrap({}) }
                end

                it "does not checks the root dir if check_root_dir_empty? returns false" do
                    flexmock(@ops).should_receive(:check_root_dir_empty?)
                                  .and_return(false)
                    flexmock(@ops).should_receive(:check_root_dir_empty).never
                    flexmock(@ops).should_receive(:validate_autoproj_current_root)
                                  .and_throw(:bypass)
                    assert_throws(:bypass) { @ops.bootstrap({}) }
                end
            end
        end
    end
end
