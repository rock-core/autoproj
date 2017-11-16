require 'autoproj/test'

describe Autoproj do
    describe ".report" do
        describe "on_package_failures: :report" do
            before do
                @exception = Autobuild::Exception.new("test", "test")
                ws_create
                @pkg = ws_define_package :cmake, 'test'
            end

            it "returns an exception raised by the block and reports it" do
                flexmock(Autobuild::Reporting).should_receive(:error).once
                flexmock(Autoproj).should_receive(:report_interrupt).never
                result = Autoproj.report(on_package_failures: :report) do
                    raise @exception
                end
                assert_equal [@exception], result
            end
            it "returns an exception stored in a package's failures and reports it" do
                flexmock(Autobuild::Reporting).should_receive(:error).once
                flexmock(Autoproj).should_receive(:report_interrupt).never
                result = Autoproj.report(on_package_failures: :report) do
                    @pkg.autobuild.failures << @exception
                end
                assert_equal [@exception], result
            end
            it "passes through an Interrupt" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).once
                assert_raises(Interrupt) do
                    Autoproj.report(on_package_failures: :report) do
                        raise Interrupt
                    end
                end
            end
            it "displays the pending package errors on Interrupt" do
                flexmock(Autobuild::Reporting).should_receive(:error).once
                flexmock(Autoproj).should_receive(:report_interrupt).once
                assert_raises(Interrupt) do
                    Autoproj.report(on_package_failures: :report) do
                        @pkg.autobuild.failures << @exception
                        raise Interrupt
                    end
                end
            end
            it "passes through SystemExit" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(SystemExit) do
                    Autoproj.report(on_package_failures: :report) do
                        exit 0
                    end
                end
            end
        end
        describe "on_package_failures: :report_silent" do
            before do
                @exception = Autobuild::Exception.new("test", "test")
                ws_create
                @pkg = ws_define_package :cmake, 'test'
            end

            it "returns an exception raised by the block and reports it" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                result = Autoproj.report(on_package_failures: :report_silent) do
                    raise @exception
                end
                assert_equal [@exception], result
            end
            it "returns an exception stored in a package's failures and reports it" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                result = Autoproj.report(on_package_failures: :report_silent) do
                    @pkg.autobuild.failures << @exception
                end
                assert_equal [@exception], result
            end
            it "passes through an Interrupt" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(Interrupt) do
                    Autoproj.report(on_package_failures: :report_silent) do
                        raise Interrupt
                    end
                end
            end
            it "displays the pending package errors on Interrupt" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(Interrupt) do
                    Autoproj.report(on_package_failures: :report_silent) do
                        @pkg.autobuild.failures << @exception
                        raise Interrupt
                    end
                end
            end
            it "passes through SystemExit" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(SystemExit) do
                    Autoproj.report(on_package_failures: :report_silent) do
                        exit 0
                    end
                end
            end
        end
        describe "on_package_failures: :exit" do
            before do
                @exception = Autobuild::Exception.new("test", "test")
                ws_create
                @pkg = ws_define_package :cmake, 'test'
            end

            it "returns an exception raised by the block and exits" do
                flexmock(Autobuild::Reporting).should_receive(:error).with(@exception).once
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(SystemExit) do
                    Autoproj.report(on_package_failures: :exit) do
                        raise @exception
                    end
                end
            end
            it "returns an exception stored in a package's failures and exits" do
                flexmock(Autobuild::Reporting).should_receive(:error).with(@exception).once
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(SystemExit) do
                    Autoproj.report(on_package_failures: :exit) do
                        @pkg.autobuild.failures << @exception
                    end
                end
            end
            it "passes through an Interrupt" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).once
                assert_raises(Interrupt) do
                    Autoproj.report(on_package_failures: :exit) do
                        raise Interrupt
                    end
                end
            end
            it "exits on Interrupt if there are pending package errors" do
                flexmock(Autobuild::Reporting).should_receive(:error).with(@exception).once
                flexmock(Autoproj).should_receive(:report_interrupt).once
                assert_raises(SystemExit) do
                    Autoproj.report(on_package_failures: :exit) do
                        @pkg.autobuild.failures << @exception
                        raise Interrupt
                    end
                end
            end
            it "passes through SystemExit" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(SystemExit) do
                    Autoproj.report(on_package_failures: :exit) do
                        exit 0
                    end
                end
            end
        end
        describe "on_package_failures: :exit_silent" do
            before do
                @exception = Autobuild::Exception.new("test", "test")
                ws_create
                @pkg = ws_define_package :cmake, 'test'
            end

            it "exits without reporting an exception raised by the block" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(SystemExit) do
                    Autoproj.report(on_package_failures: :exit_silent) do
                        raise @exception
                    end
                end
            end
            it "exits without reporting a package failure" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(SystemExit) do
                    Autoproj.report(on_package_failures: :exit_silent) do
                        @pkg.autobuild.failures << @exception
                    end
                end
            end
            it "passes through an Interrupt" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(Interrupt) do
                    Autoproj.report(on_package_failures: :exit_silent) do
                        raise Interrupt
                    end
                end
            end
            it "exits on Interrupt if there are pending package errors, without reporting them" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(SystemExit) do
                    Autoproj.report(on_package_failures: :exit_silent) do
                        @pkg.autobuild.failures << @exception
                        raise Interrupt
                    end
                end
            end
            it "passes through SystemExit" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(SystemExit) do
                    Autoproj.report(on_package_failures: :exit_silent) do
                        exit 0
                    end
                end
            end
        end
        describe "on_package_failures: :raise" do
            before do
                @exception = Autobuild::Exception.new("test", "test")
                ws_create
                @pkg = ws_define_package :cmake, 'test'
            end

            it "passes through an exception raised by the block" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(@exception.class) do
                    Autoproj.report(on_package_failures: :raise) do
                        raise @exception
                    end
                end
            end
            it "raises a package failure" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(@exception.class) do
                    Autoproj.report(on_package_failures: :raise) do
                        @pkg.autobuild.failures << @exception
                    end
                end
            end
            it "aggregates multiple exceptions into a CompositeException before raising it" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(Autobuild::CompositeException) do
                    Autoproj.report(on_package_failures: :raise) do
                        @pkg.autobuild.failures << @exception
                        @pkg.autobuild.failures << @exception
                    end
                end
            end
            it "passes through an Interrupt" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).once
                assert_raises(Interrupt) do
                    Autoproj.report(on_package_failures: :raise) do
                        raise Interrupt
                    end
                end
            end
            it "raises Interrupt if there are pending package errors but Interrupt is raised" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).once
                assert_raises(Interrupt) do
                    Autoproj.report(on_package_failures: :raise) do
                        @pkg.autobuild.failures << @exception
                        raise Interrupt
                    end
                end
            end
            it "passes through SystemExit" do
                flexmock(Autobuild::Reporting).should_receive(:error).never
                flexmock(Autoproj).should_receive(:report_interrupt).never
                assert_raises(SystemExit) do
                    Autoproj.report(on_package_failures: :raise) do
                        exit 0
                    end
                end
            end
        end
    end
end
