require 'autoproj/test'
require 'autoproj/cli/main'
require 'autoproj/cli/version'

module Autoproj
    module CLI
        describe Version do
            before do
                @autoproj_bin = File.expand_path(File.join("..", "..", "bin", "autoproj"), __dir__)
            end

            describe "version" do
                it "simple version" do
                    assert_output(/autoproj version: #{Autoproj::VERSION}/) do
                        Main.start(["version"])
                    end
                end
                it "version with dependencies" do
                    # 'm' for make dot match newline
                    assert_output(/autoproj version: #{Autoproj::VERSION}\n.*specified.*autobuild.*/m) do
                        Main.start(["version","--deps"])
                    end
                end
            end
        end
    end
end


