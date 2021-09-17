require "autoproj/test"
require "autoproj/cli/cache"

module Autoproj
    module CLI
        describe Cache do
            before do
                @ws = ws_create
                @cli = Cache.new(@ws)
            end

            describe "#validate_options" do
                after do
                    Autobuild::Importer.default_cache_dirs = nil
                end

                it "uses the default cache dir if no arguments are given" do
                    Autobuild::Importer.default_cache_dirs = "/some/path"
                    *argv, _options = @cli.validate_options([], {})
                    assert_equal ["/some/path"], argv
                end

                it "raises if no arguments are given and there is no default" do
                    Autobuild::Importer.default_cache_dirs = nil
                    assert_raises(CLIInvalidArguments) do
                        @cli.validate_options([], {})
                    end
                end

                it "parses the gem compile option" do
                    flexmock(@cli).should_receive(:parse_gem_compile)
                                  .with(name = flexmock)
                                  .and_return(parsed_gem = flexmock)
                    _, options = @cli.validate_options(
                        ["/cache/path"], gems_compile: [name]
                    )
                    assert_equal [parsed_gem], options[:gems_compile]
                end

                it "interprets the + signs in the gems_compile option" do
                    _, options = @cli.validate_options(
                        ["/cache/path"], gems_compile: ["some_gem[+artifact/path][-some/other]"]
                    )
                    assert_equal [["some_gem", artifacts: [[true, "artifact/path"], [false, "some/other"]]]],
                                 options[:gems_compile]
                end
            end

            describe "#parse_gem_compile" do
                it "handles a plain gem" do
                    assert_equal ["some_gem", artifacts: []],
                                 @cli.parse_gem_compile("some_gem")
                end

                it "handles a single artifact inclusion specification" do
                    assert_equal ["some_gem", artifacts: [[true, "some/artifact"]]],
                                 @cli.parse_gem_compile("some_gem[+some/artifact]")
                end

                it "handles a single artifact exclusion specification" do
                    assert_equal ["some_gem", artifacts: [[false, "some/artifact"]]],
                                 @cli.parse_gem_compile("some_gem[-some/artifact]")
                end

                it "handles a sequence of artifact specification" do
                    string = "some_gem[+bla/bla][-some/artifact]"
                    expected = [
                        "some_gem",
                        artifacts: [
                            [true, "bla/bla"],
                            [false, "some/artifact"]
                        ]
                    ]
                    assert_equal expected, @cli.parse_gem_compile(string)
                end

                it "detects a missing closing bracket" do
                    assert_raises(ArgumentError) do
                        @cli.parse_gem_compile("some_gem[+some")
                    end
                end

                it "detects a single opening bracket at the end" do
                    assert_raises(ArgumentError) do
                        @cli.parse_gem_compile("some_gem[")
                    end
                end

                it "detects a missing +/-" do
                    assert_raises(ArgumentError) do
                        @cli.parse_gem_compile("some_gem[bla]")
                    end
                end

                it "detects an empty [] specification" do
                    assert_raises(ArgumentError) do
                        @cli.parse_gem_compile("some_gem[]")
                    end
                end
            end
        end
    end
end
