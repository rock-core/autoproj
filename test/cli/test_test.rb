require "autoproj/test"
require "autoproj/cli/test"
require "timecop"

module Autoproj
    module CLI
        describe Test do
            attr_reader :cli
            attr_reader :ws
            before do
                @ws = ws_create
                @one = ws_add_package_to_layout :cmake, "one"
                @two = ws_add_package_to_layout :cmake, "two"
                @three = ws_define_package :cmake, "three"

                @report_path = @ws.utility_report_path("unittest")
                @cli = Test.new(ws, report_path: @report_path)
                flexmock(cli)
            end

            describe "#run" do
                it "validates user selection" do
                    cli.run(%w[one two])
                end
                it "throws if one of the packages is not defined" do
                    assert_raises(Autoproj::CLI::CLIInvalidArguments) do
                        cli.run(%w[one two foo])
                    end
                end
                it "throws if the selected package is excluded from build" do
                    ws.manifest.exclude_package("two", "test")
                    assert_raises(Autoproj::CLI::CLIInvalidSelection) do
                        cli.run(%w[two])
                    end
                end
                it "throws if the selected package is not in the layout" do
                    ws.manifest.ignore_package("three")
                    assert_raises(Autoproj::CLI::CLIInvalidArguments) do
                        cli.run(%w[three])
                    end
                end
            end

            describe "#apply_to_packages" do
                after do
                    Timecop.return
                end

                it "reports the coverage status in addition to basic utility info" do
                    a = @one.autobuild.test_utility
                    a.source_dir = "/some/path"
                    a.target_dir = "/some/other/path"
                    a.task {}
                    a.coverage_enabled = false
                    a.coverage_source_dir = "/coverage/source/path"
                    a.coverage_target_dir = nil
                    @cli.apply_to_packages([@one])

                    Timecop.freeze
                    report = JSON.load(File.read(@report_path))
                    assert_equal Time.now.to_s, report["test_report"]["timestamp"]
                    packages = report["test_report"]["packages"]
                    assert_equal 1, packages.size
                    assert(one = packages["one"])
                    assert one.key?("coverage_enabled")
                    assert_equal "/some/path", one["source_dir"]
                    assert_equal "/some/other/path", one["target_dir"]
                    assert_same true, one["available"]
                    assert_same false, one["enabled"]
                    assert_same false, one["invoked"]
                    assert_same false, one["success"]
                    assert_same false, one["installed"]

                    assert_equal "/coverage/source/path", one["coverage_source_dir"]
                    assert_equal "/some/other/path/coverage", one["coverage_target_dir"]
                    assert_same true, one["coverage_available"]
                    assert_same false, one["coverage_enabled"]
                end
            end
        end
    end
end
