require 'autoproj/test'

module Autoproj
    describe Configuration do
        before do
            @config = Configuration.new
        end

        describe "#to_hash" do
            it "returns the key=>value mapping" do
                @config.set 'test', 'value'
                assert_equal Hash['test' => 'value'], @config.to_hash
            end
        end
    end
end


