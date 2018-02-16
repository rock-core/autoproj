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

        describe "#reset" do
            it "sets modified? if the configuration contained the key" do
                @config.set "test", "value"
                @config.reset_modified
                @config.reset 'test'
                assert @config.modified?
            end
            it "does not set modified? if the configuration did not contain the key" do
                @config.reset 'test'
                refute @config.modified?
            end
        end

        describe "#set" do
            it "sets modified? if writing a new value" do
                @config.set "test", "value"
                assert @config.modified?
            end
            it "sets modified? if modifying an existing value" do
                @config.set "test", "value"
                @config.reset_modified
                @config.set "test", "new_value"
                assert @config.modified?
            end
            it "does not set modified? if it does not set a new value" do
                @config.set "test", "value"
                @config.reset_modified
                @config.set "test", "value"
                refute @config.modified?
            end
        end

        describe "#override" do
            describe "overriding an unset value" do
                before do
                    @config.override 'test', 'something'
                end
                it "does not set modified?" do
                    refute @config.modified?
                end
            end
            describe "overriding an existing value" do
                before do
                    @config.set 'test', 'value'
                    @config.reset_modified
                    @config.override 'test', 'something'
                end
                it "does not set modified?" do
                    refute @config.modified?
                end
            end
        end

        describe "#load" do
            it "resets the modified flag if all existing values are overriden by values on file" do
                path = File.join(make_tmpdir, 'config.yml')
                @config.set 'test', 'value'
                File.open(path, 'w') { |io| YAML.dump(Hash['test' => 'something'], io) }
                @config.load(path: path)
                refute @config.modified?
            end
            it "does not set the modified flag if the configuration was empty" do
                path = File.join(make_tmpdir, 'config.yml')
                File.open(path, 'w') { |io| YAML.dump(Hash['test' => 'something'], io) }
                @config.load(path: path)
                refute @config.modified?
            end
            it "keeps the modified flag if set values were not present on disk" do
                path = File.join(make_tmpdir, 'config.yml')
                File.open(path, 'w') { |io| YAML.dump(Hash['test' => 'something'], io) }
                @config.set 'other', 'value'
                @config.load(path: path)
                assert @config.modified?
            end
        end

        describe "#save" do
            it "resets the modified flag" do
                path = File.join(make_tmpdir, 'config.yml')
                @config.set 'test', 'value'
                @config.save path
                refute @config.modified?
            end
        end
    end
end


