require "autoproj/test"

module Autoproj
    describe Configuration do
        before do
            @config = Configuration.new
        end

        describe "#to_hash" do
            it "returns the key=>value mapping" do
                @config.set "test", "value"
                assert_equal Hash["test" => "value"], @config.to_hash
            end
        end

        describe "#reset" do
            it "deletes the given value" do
                @config.set "test", "value"
                @config.reset "test"
                assert_equal Hash.new, @config.to_hash
            end
            it "sets modified? if the configuration contained the key" do
                @config.set "test", "value"
                @config.reset_modified
                @config.reset "test"
                assert @config.modified?
            end
            it "does not set modified? if the configuration did not contain the key" do
                @config.reset "test"
                refute @config.modified?
            end
            it "does not reset modified? when the configuration did not contain the key" do
                @config.set "test", "value"
                assert @config.modified?
                @config.reset "test"
                assert @config.modified?
            end
            it "deletes an existing override" do
                @config.override "test", "value"
                @config.reset "test"
                assert_equal Hash.new, @config.to_hash
            end
            it "does not set modified? if all there was was an override" do
                @config.override "test", "value"
                @config.reset "test"
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
            it "does not reset modified? when writing an old value" do
                @config.set "test", "value"
                @config.set "test", "value"
                assert @config.modified?
            end
            it "does not set modified? if it does not set a new value even if the value is nil" do
                @config.set "test", nil
                @config.reset_modified
                @config.set "test", nil
                refute @config.modified?
            end
            it "does not reset modified? when writing an old value, even if this value is nil" do
                @config.set "test", nil
                @config.set "test", nil
                assert @config.modified?
            end
        end

        describe "#override" do
            describe "overriding an unset value" do
                before do
                    @config.override "test", "something"
                end
                it "changes the value returned by #get" do
                    assert_equal "something", @config.get("test")
                end
                it "changes the value returned by #to_hash" do
                    assert_equal Hash["test" => "something"], @config.to_hash
                end
                it "does not change the value on disk" do
                    path = File.join(make_tmpdir, "config.yml")
                    @config.save path, force: true
                    assert_equal Hash[], YAML.load(File.read(path))
                end
                it "does not set modified?" do
                    refute @config.modified?
                end
                it "ensures that has_value_for? returns true" do
                    assert @config.has_value_for?("test")
                end
                it "handles overriding with a nil as value" do
                    @config.override "test", nil
                    assert_nil @config.get("test")
                    assert_equal Hash["test" => nil], @config.to_hash
                end
            end
            describe "overriding an existing value" do
                before do
                    @config.set "test", "value"
                    @config.reset_modified
                    @config.override "test", "something"
                end
                it "changes the value returned by #get" do
                    assert_equal "something", @config.get("test")
                end
                it "changes the value returned by #to_hash" do
                    assert_equal Hash["test" => "something"], @config.to_hash
                end
                it "does not change the value on disk" do
                    path = File.join(make_tmpdir, "config.yml")
                    @config.save path, force: true
                    assert_equal Hash["test" => "value"], YAML.load(File.read(path))
                end
                it "does not set modified?" do
                    refute @config.modified?
                end
                it "ensures that has_value_for? returns true" do
                    assert @config.has_value_for?("test")
                end
                it "handles overriding with a nil as value" do
                    @config.override "test", nil
                    assert_nil @config.get("test")
                    assert_equal Hash["test" => nil], @config.to_hash
                end
            end
        end

        describe "#get" do
            describe "undeclared options" do
                it "returns a copy of set value" do
                    @config.set "test", "value"
                    assert_equal "value", @config.get("test")
                end
                it "dups the value before returning it" do
                    @config.set "test", "value"
                    old = @config.get("test")
                    refute_same old, @config.get("test")
                end
                it "returns the default if one is given" do
                    assert_equal "value", @config.get("test", "value")
                end
                it "dups the default value before returning it" do
                    default = "value"
                    refute_same default, @config.get("test", default)
                end
                it "raises if it is unset and no default is given" do
                    e = assert_raises(Autoproj::ConfigError) do
                        @config.get("test")
                    end
                    assert_equal "undeclared option 'test'", e.message
                end
            end
            describe "declared options" do
                before do
                    flexmock(@config)
                    @config.declare "test", "string"
                end
                it "configures it if it is unset" do
                    @config.should_receive(:configure).with("test").and_return("value")
                    assert_equal "value", @config.get("test")
                end
                it "dups the configured value before returning it" do
                    value = "value"
                    @config.should_receive(:configure).with("test").and_return(value)
                    refute_same value, @config.get("test")
                end
                it "configures it if it is set but unvalidated" do
                    @config.set "test", "value"
                    @config.should_receive(:configure).with("test").and_return("value")
                    assert_equal "value", @config.get("test")
                end
                it "dups the unvalidated value before returning it" do
                    @config.set "test", "value"
                    value = "value"
                    @config.should_receive(:configure).with("test").and_return(value)
                    refute_same value, @config.get("test")
                end
                it "returns it if it is set and validated" do
                    @config.set "test", "value", true
                    assert_equal "value", @config.get("test")
                end
                it "dups the validated value before returning it" do
                    value = "value"
                    @config.set "test", value, true
                    refute_same value, @config.get("test")
                end
            end
        end

        describe "#load" do
            it "resets the modified flag if all existing values are overriden by values on file" do
                path = File.join(make_tmpdir, "config.yml")
                @config.set "test", "value"
                File.open(path, "w") { |io| YAML.dump(Hash["test" => "something"], io) }
                @config.load(path: path)
                refute @config.modified?
            end
            it "does not set the modified flag if the configuration was empty" do
                path = File.join(make_tmpdir, "config.yml")
                File.open(path, "w") { |io| YAML.dump(Hash["test" => "something"], io) }
                @config.load(path: path)
                refute @config.modified?
            end
            it "keeps the modified flag if set values were not present on disk" do
                path = File.join(make_tmpdir, "config.yml")
                File.open(path, "w") { |io| YAML.dump(Hash["test" => "something"], io) }
                @config.set "other", "value"
                @config.load(path: path)
                assert @config.modified?
            end
        end

        describe "#save" do
            it "resets the modified flag" do
                path = File.join(make_tmpdir, "config.yml")
                @config.set "test", "value"
                @config.save path
                refute @config.modified?
            end
        end

        describe "#utility_enable" do
            before do
                @config.utility_enable "test", "my/package"
            end
            it "enables the utility for the given packages" do
                assert @config.utility_enabled_for?("test", "my/package")
            end
            it "dirties the configuration if the utility was not enabled already" do
                assert @config.modified?
            end
            it "does not dirties the configuration if the utility was already enabled" do
                @config.reset_modified
                @config.utility_enable "test", "my/package"
                refute @config.modified?
            end
        end

        describe "#utility_enable_all" do
            it "enables the utility for all packages" do
                @config.utility_enable_all("test")
                assert @config.utility_enabled_for?("test", "my/package")
            end
            it "dirties the configuration if it was globally disabled" do
                @config.utility_enable_all("test")
                assert @config.modified?
            end
            it "dirties the configuration if some packages had specific settings" do
                @config.utility_enable("test", "my/package")
                @config.reset_modified
                @config.utility_enable_all("test")
                assert @config.modified?
            end
            it "allows disabling per-package" do
                @config.utility_enable_all("test")
                @config.utility_disable "test", "my/package"
                refute @config.utility_enabled_for?("test", "my/package")
            end
            it "does not dirties the configuration if the utility was already globally enabled" do
                @config.utility_enable_all("test")
                @config.reset_modified
                @config.utility_enable_all("test")
                refute @config.modified?
            end
        end

        describe "#utility_disable" do
            before do
                @config.utility_enable("test", "my/package")
                @config.reset_modified
                @config.utility_disable "test", "my/package"
            end
            it "disables the utility for the given packages" do
                refute @config.utility_enabled_for?("test", "my/package")
            end
            it "dirties the configuration if the utility was enabled" do
                assert @config.modified?
            end
            it "does not dirties the configuration if the utility was already disabled" do
                @config.reset_modified
                @config.utility_disable "test", "my/package"
                refute @config.modified?
            end
        end

        describe "#utility_disable_all" do
            it "disables the utility for all packages" do
                @config.utility_disable_all("test")
                refute @config.utility_enabled_for?("test", "my/package")
            end
            it "dirties the configuration if it was globally enabled" do
                @config.utility_enable_all("test")
                @config.reset_modified
                @config.utility_disable_all("test")
                assert @config.modified?
            end
            it "dirties the configuration if some packages had specific settings" do
                @config.utility_enable("test", "my/package")
                @config.reset_modified
                @config.utility_disable_all("test")
                assert @config.modified?
            end
            it "allows enabling per-package" do
                @config.utility_disable_all("test")
                @config.utility_enable "test", "my/package"
                assert @config.utility_enabled_for?("test", "my/package")
            end
            it "does not dirty the configuration if the utility was already globally disabled" do
                @config.utility_disable_all("test")
                @config.reset_modified
                @config.utility_disable_all("test")
                refute @config.modified?
            end
        end
        describe "#interactive" do
            it "set interactive mode" do
                @config.interactive = false
                assert !@config.interactive?

                @config.interactive = true
                assert @config.interactive?
            end

            it "disables interactive configuration setting through config option" do
                option_name = "custom-configuration-option"
                default_value = "option-defaultvalue"
                @config.declare(option_name, "string", default: default_value)

                @config.interactive = false

                Timeout.timeout(3) do
                    @config.configure(option_name)
                end
                assert @config.get(option_name) == default_value
            end

            it "disables interactive configuration setting through ENV" do
                option_name = "custom-configuration-option"
                default_value = "option-defaultvalue"
                @config.declare(option_name, "string", default: default_value)

                ENV["AUTOPROJ_NONINTERACTIVE"] = "1"

                assert !@config.interactive?
                begin
                    Timeout.timeout(3) do
                        @config.configure(option_name)
                    end
                    assert @config.get(option_name) == default_value
                ensure
                    ENV.delete("AUTOPROJ_NONINTERACTIVE")
                end
            end
            it "use interactive configuration by default" do
                option_name = "custom-configuration-option"
                default_value = "option-defaultvalue"
                @config.declare(option_name, "string", default: default_value)
                assert @config.interactive?
                assert_raises Timeout::Error, EOFError do
                    Timeout.timeout(3) do
                        @config.configure(option_name)
                    end
                end
            end
            it "properly validates the default value" do
                option_name = "custom-configuration-option"
                default_value = "no"
                @config.interactive = false
                @config.declare(option_name, "boolean", default: default_value)
                refute @config.configure(option_name)
                assert_kind_of FalseClass, @config.configure(option_name)
            end
            it "skip saving default value" do
                option_a_name = "custom-configuration-option-a"
                default_a_value = "option-a-defaultvalue"

                option_b_name = "custom-configuration-option-b"
                default_b_value = "option-b-default-value"
                b_value = "option-b-value"

                @config.declare(option_a_name, "string", default: default_a_value)
                @config.declare(option_b_name, "string", default: default_b_value)

                @config.interactive = false
                @config.configure(option_a_name)
                @config.set(option_b_name, b_value)
                @config.configure(option_b_name)

                assert !@config.has_value_for?(option_a_name)
                assert @config.has_value_for?(option_b_name)

                tempfile = Tempfile.new("skip-saving-config")
                @config.save(tempfile)

                loaded_config = Configuration.new(tempfile)
                loaded_config.load
                assert !loaded_config.has_value_for?(option_a_name)
                assert loaded_config.has_value_for?(option_b_name)
                assert loaded_config.get(option_b_name) == b_value
            end
        end

        describe "#load_config_once" do
            it "load config once loads config only once" do
                # construct global path for test seed, (autoproj.config_dir not available here)
                seed_file = File.dirname(__FILE__) + "/data/test_manifest/autoproj/test_config_seed.yml"

                config_name = "load_config_once_testvalue"
                @config.declare(config_name, "boolean", default: "no")
                @config.interactive = false
                @config.configure(config_name)

                @config.load_config_once(seed_file)

                assert @config.modified?
                assert @config.has_value_for?(config_name)
                assert @config.get(config_name)

                # reset value to one not in config
                @config.set(config_name, "value not in the seed config")
                # load config again (conten true)
                @config.load_config_once(seed_file)
                # should still have the naually set value (false)
                assert @config.get(config_name) == "value not in the seed config"
            end

            it "load config once with permission: do load" do
                # construct global path for test seed, (autoproj.config_dir not available here)
                seed_file = "#{File.dirname(__FILE__)}/data/test_manifest/autoproj/test_config_seed.yml"

                config_name = "load_config_once_testvalue"
                @config.declare(config_name, "boolean", default: "no")
                @config.interactive = false
                @config.configure(config_name)

                @config.load_config_once_with_permission(seed_file)

                assert @config.modified?
                assert @config.has_value_for?(config_name)
                assert @config.get(config_name)
            end

            it "load config once with permission: don't load" do
                # construct global path for test seed, (autoproj.config_dir not available here)
                seed_file = "#{File.dirname(__FILE__)}/data/test_manifest/autoproj/test_config_seed.yml"

                config_name = "load_config_once_testvalue"
                @config.declare(config_name, "boolean", default: "no")
                @config.interactive = false
                @config.configure(config_name)

                # now the use_default_config is set to false, no loading should happen
                @config.load_config_once_with_permission(seed_file, default: "no")
                # value should still be the same (no loading)
                assert @config.get(config_name) == false
            end
        end
    end
end
