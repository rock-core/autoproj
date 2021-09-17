require "autoproj/test"
require "autoproj/cli/tag"
module Autoproj
    module CLI
        describe Tag do
            it "raises CLIInvalidArguments if the main build configuration does not have an importer" do
                ws_create
                assert_raises(CLIInvalidArguments) do
                    Tag.new(ws).run("tagname")
                end
            end
            it "raises CLIInvalidArguments if the main build configuration's importer is not git" do
                ws_create
                assert_raises(CLIInvalidArguments) do
                    Tag.new(ws).run("tagname")
                end
            end
        end
    end
end
