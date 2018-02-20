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
            it "deletes the given value" do
                @config.set "test", "value"
                @config.reset 'test'
                assert_equal Hash.new, @config.to_hash
            end
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
            it "deletes an existing override" do
                @config.override 'test', 'value'
                @config.reset 'test'
                assert_equal Hash.new, @config.to_hash
            end
            it "does not set modified? if all there was was an override" do
                @config.override 'test', 'value'
                @config.reset 'test'
                refute @config.modified?
            end
        end

        describe "#set" do
            it "sets a new key-value pair" do
                @config.set "test", "value"
                assert_equal "value", @config.get("test")
            end
            it "accepts nil as a valid value" do
                @config.set "test", nil
                assert_nil @config.get("test")
            end
            it "sets modified? if writing a new value" do
                @config.set "test", "value"
                assert @config.modified?
            end
            it "sets modified? if writing nil as a new value" do
                @config.set "test", nil
                assert @config.modified?
            end
            it "sets modified? if modifying an existing value" do
                @config.set "test", "value"
                @config.reset_modified
                @config.set "test", "new_value"
                assert @config.modified?
            end
            it "sets modified? if modifying an existing value to set nil" do
                @config.set "test", "value"
                @config.reset_modified
                @config.set "test", nil
                assert @config.modified?
            end
            it "does not set modified? if it does not set a new value" do
                @config.set "test", "value"
                @config.reset_modified
                @config.set "test", "value"
                refute @config.modified?
            end
            it "does not set modified? if it does not set a new value even if the value is nil" do
                @config.set "test", nil
                @config.reset_modified
                @config.set "test", nil
                refute @config.modified?
            end
        end

        describe "#override" do
            describe "overriding an unset value" do
                before do
                    @config.override 'test', 'something'
                end
                it "changes the value returned by #get" do
                    assert_equal 'something', @config.get('test')
                end
                it "changes the value returned by #to_hash" do
                    assert_equal Hash['test' => 'something'], @config.to_hash
                end
                it "does not change the value on disk" do
                    path = File.join(make_tmpdir, 'config.yml')
                    @config.save path, force: true
                    assert_equal Hash[], YAML.load(File.read(path))
                end
                it "does not set modified?" do
                    refute @config.modified?
                end
                it "ensures that has_value_for? returns true" do
                    assert @config.has_value_for?('test')
                end
                it "handles overriding with a nil as value" do
                    @config.override 'test', nil
                    assert_nil @config.get('test')
                    assert_equal Hash['test' => nil], @config.to_hash
                end
            end
            describe "overriding an existing value" do
                before do
                    @config.set 'test', 'value'
                    @config.reset_modified
                    @config.override 'test', 'something'
                end
                it "changes the value returned by #get" do
                    assert_equal 'something', @config.get('test')
                end
                it "changes the value returned by #to_hash" do
                    assert_equal Hash['test' => 'something'], @config.to_hash
                end
                it "does not change the value on disk" do
                    path = File.join(make_tmpdir, 'config.yml')
                    @config.save path, force: true
                    assert_equal Hash['test' => 'value'], YAML.load(File.read(path))
                end
                it "does not set modified?" do
                    refute @config.modified?
                end
                it "ensures that has_value_for? returns true" do
                    assert @config.has_value_for?('test')
                end
                it "handles overriding with a nil as value" do
                    @config.override 'test', nil
                    assert_nil @config.get('test')
                    assert_equal Hash['test' => nil], @config.to_hash
                end
            end
        end

        describe "#get" do
            describe "undeclared options" do
                it "returns the set value" do
                    @config.set 'test', 'value'
                    assert_equal 'value', @config.get('test')
                end
                it "returns the default if one is given" do
                    assert_equal 'value', @config.get('test', 'value')
                end
                it "raises if it is unset and no default is given" do
                    e = assert_raises(Autoproj::ConfigError) do
                        @config.get('test')
                    end
                    assert_equal "undeclared option 'test'", e.message
                end
            end
            describe "declared options" do
                before do
                    flexmock(@config)
                    @config.declare 'test', 'string'
                end
                it "configures it if it is unset" do
                    @config.should_receive(:configure).with('test').and_return('value')
                    assert_equal 'value', @config.get('test')
                end
                it "configures it if it is set but unvalidated" do
                    @config.set 'test', 'value'
                    @config.should_receive(:configure).with('test').and_return('value')
                    assert_equal 'value', @config.get('test')
                end
                it "returns it if it is set and validated" do
                    @config.set 'test', 'value', true
                    assert_equal 'value', @config.get('test')
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


