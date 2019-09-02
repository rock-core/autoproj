require 'autoproj/test'
require 'autoproj/cli/utility'
require 'timecop'

module Autoproj
    module CLI
        describe Utility do
            attr_reader :cli
            attr_reader :ws
            before do
                @ws = ws_create
                @one = ws_add_package_to_layout :cmake, 'one'
                @two = ws_add_package_to_layout :cmake, 'two'
                @three = ws_define_package :cmake, 'three'

                @utility_class = Class.new(Autobuild::Utility)
                Autobuild.register_utility_class(
                    'unittest', @utility_class
                )

                @report_path = @ws.utility_report_path('unittest')
                @cli = Utility.new(ws, name: 'unittest', report_path: @report_path)
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
                    ws.manifest.exclude_package('two', 'test')
                    assert_raises(Autoproj::CLI::CLIInvalidSelection) do
                        cli.run(%w[two])
                    end
                end
                it "throws if the selected package is not in the layout" do
                    ws.manifest.ignore_package('three')
                    assert_raises(Autoproj::CLI::CLIInvalidArguments) do
                        cli.run(%w[three])
                    end
                end
                it "generates a report if successful" do
                    @cli.should_receive(:create_report)
                        .with([@one, @two]).once
                    cli.run(%w[one two])
                end

                it "creates a report on success" do
                    @cli.should_receive(:create_report)
                        .with([@one, @two]).once
                    flexmock(Autobuild).should_receive(:apply)
                    @cli.run(%w[one two])
                end

                it "creates a report on failure" do
                    @cli.should_receive(:create_report)
                        .with([@one, @two]).once
                    flexmock(Autobuild).should_receive(:apply)
                                       .and_raise(e = Class.new(Exception))
                    assert_raises(e) { @cli.run(%w[one two]) }
                end

                it "does not create a report if the package resolution fails" do
                    flexmock(@cli).should_receive(:create_report).never
                    flexmock(@cli).should_receive(:finalize_setup)
                                  .and_raise(e = Class.new(Exception))
                    assert_raises(e) do
                        @cli.run(%w[one two])
                    end
                end
            end

            describe "#create_report" do
                after do
                    Timecop.return
                end

                it "reports the status of the utility" do
                    a = @one.autobuild.unittest_utility
                    a.source_dir = "/some/path"
                    a.target_dir = "/some/other/path"
                    a.task {}
                    @cli.create_report([@one])

                    Timecop.freeze
                    report = JSON.load(File.read(@report_path))
                    assert_equal Time.now.to_s, report['unittest_report']['timestamp']
                    packages = report['unittest_report']['packages']
                    assert_equal 1, packages.size
                    assert(one = packages['one'])
                    assert_equal '/some/path', one['source_dir']
                    assert_equal '/some/other/path', one['target_dir']
                    assert_same true, one['available']
                    assert_same true, one['enabled']
                    assert_same false, one['invoked']
                    assert_same false, one['success']
                    assert_same false, one['installed']
                end
            end
        end
    end
end
