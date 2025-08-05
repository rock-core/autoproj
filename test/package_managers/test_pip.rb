require "autoproj/test"

module Autoproj
    module PackageManagers
        describe PipManager do
            attr_reader :pip_manager

            def setup
                super

                ws_create
                ws.config.set("USE_PYTHON", true)

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
    end
end
