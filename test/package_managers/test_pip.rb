require "autoproj/test"

module Autoproj
    module PackageManagers
        describe PipManager do
            attr_reader :pip_manager

            def setup
                super

                ws_create
                ws.config.set("USE_PYTHON", true)
                ws.config.set("USE_PYTHON_VENV", false, true)

                @pip_manager = PipManager.new(ws)
                Autobuild.programs["pip"] = "mypip"
            end

            def teardown
                super
                Autobuild.programs["pip"] = nil
            end

            def test_install_packages
                subprocess = flexmock(Autobuild::Subprocess)

                packages = %w[pkg0 pkg1 pkg2]
                subprocess.should_receive(:run).explicitly
                          .with(any, any, "mypip", "install", "--user", "pkg0", "pkg1", "pkg2")
                          .with_any_kw_args.once
                ws.config.interactive = false
                pip_manager.install(packages)
            end

            def test_install_packages_disabled_and_not_silent
                subprocess = flexmock(Autobuild::Subprocess)

                pip_manager.enabled = false
                pip_manager.silent = false
                subprocess.should_receive(:run).explicitly.never
                flexmock($stdin).should_receive(:readline).once.and_return
                ws.config.interactive = false
                ws.config.set("USE_PYTHON", true, true)
                pip_manager.install([["pkg0"]])
            end

            def test_no_use_python
                ws.config.set("USE_PYTHON", false, true)
                ws.config.interactive = false
                assert_raises(ConfigError) { pip_manager.guess_pip_program }
                ws.config.set("USE_PYTHON", true)
            end

            def test_unspecified_python
                ws.config.reset("USE_PYTHON")
                assert(!ws.config.has_value_for?("USE_PYTHON"))
                interactive = ws.config.interactive
                ws.config.interactive = false
                assert_raises(ConfigError) { pip_manager.guess_pip_program }
                ws.config.set("USE_PYTHON", true)
                ws.config.interactive = interactive
            end

            def test_python_activation_with_config_already_set
                ws.config.set("USE_PYTHON", true, true)
                flexmock(pip_manager).should_receive(:activate_python).once
                pip_manager.guess_pip_program
            end
        end

        describe "PipManager with a venv" do
            before do
                ws_create
                ws.config.interactive = false
                ws.config.set("USE_PYTHON", true, true)
                ws.config.set("USE_PYTHON_VENV", true, true)
                ws.config.set("USE_PYTHON_UV", false, true)
                @pip_manager = PipManager.new(ws)
                flexmock(@pip_manager).should_receive(:activate_python)
                ws.config.set("python_executable", "/base/python", true)
                ws.config.set("python_version", "3.12", true)
                @venv = Autoproj::Python.venv_path(ws: ws)
                @python = Autoproj::Python.venv_python(ws: ws)
                @uv = Autoproj::Python.venv_uv(ws: ws)
                @subprocess = flexmock(Autobuild::Subprocess)
                flexmock(Autoproj).should_receive(:message)
            end

            def expect_run(*cmdline)
                @subprocess.should_receive(:run).explicitly
                           .with("autoproj", "osdeps", *cmdline)
                           .with_any_kw_args.once.ordered
            end

            def make_venv_valid
                flexmock(Autoproj::Python).should_receive(:venv_valid?).and_return(true)
            end

            it "creates the venv and installs into it with pip" do
                expect_run("/base/python", "-m", "venv", "--system-site-packages", @venv)
                expect_run(@python, "-m", "pip", "install", "--upgrade", "pip")
                expect_run(@python, "-m", "pip", "install", "pkg0", "pkg1")
                @pip_manager.install(%w[pkg0 pkg1])
            end

            it "creates the venv and installs into it with uv" do
                ws.config.set("USE_PYTHON_UV", true, true)
                expect_run("/base/python", "-m", "venv", "--system-site-packages", @venv)
                expect_run(@python, "-m", "pip", "install", "--upgrade", "pip")
                expect_run(@python, "-m", "pip", "install", "uv")
                expect_run(@uv, "pip", "install", "--python", @python, "pkg0")
                @pip_manager.install(%w[pkg0])
            end

            it "only installs the packages if the venv is complete" do
                make_venv_valid
                expect_run(@python, "-m", "pip", "install", "pkg0")
                @pip_manager.install(%w[pkg0])
            end

            it "creates a missing venv even without packages" do
                expect_run("/base/python", "-m", "venv", "--system-site-packages", @venv)
                expect_run(@python, "-m", "pip", "install", "--upgrade", "pip")
                @pip_manager.install([])
            end

            it "does nothing without packages if the venv is complete" do
                make_venv_valid
                @subprocess.should_receive(:run).never
                @pip_manager.install([])
            end

            it "deletes an invalid venv before recreating it" do
                FileUtils.mkdir_p File.join(@venv, "bin")
                @subprocess.should_receive(:run).with_any_args.and_return do
                    refute File.exist?(File.join(@venv, "bin"))
                end
                @pip_manager.install(%w[pkg0])
            end

            it "reports a failure to create the venv as a configuration error" do
                @subprocess.should_receive(:run).explicitly.with_any_args
                           .and_raise(Autobuild::SubcommandFailed.new("autoproj", "venv", "log", 1))
                e = assert_raises(ConfigError) { @pip_manager.install(%w[pkg0]) }
                assert_match(/python3-venv/, e.message)
            end

            it "is called without packages only if the venv is enabled" do
                assert @pip_manager.call_while_empty?
                ws.config.set("USE_PYTHON_VENV", false, true)
                refute @pip_manager.call_while_empty?
            end

            it "requires python-venv only if the venv is enabled" do
                assert_includes @pip_manager.os_dependencies, "python-venv"
                ws.config.set("USE_PYTHON_VENV", false, true)
                refute_includes @pip_manager.os_dependencies, "python-venv"
            end
        end
    end
end
