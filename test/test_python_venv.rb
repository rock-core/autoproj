# frozen_string_literal: true

require "autoproj/test"
require "autoproj/python"

module Autoproj
    describe Python do
        before do
            ws_create
            ws.config.interactive = false
            env = Autobuild::Environment.new
            env.inherit "PATH"
            @python_bin = env.find_in_path("python3")
            skip "python3 is not available" unless @python_bin
        end

        after do
            Python.instance_variable_set(:@externally_managed, nil)
        end

        def configure_python(venv: true, use_uv: false)
            ws.config.set "USE_PYTHON", true, true
            ws.config.set "python_executable", @python_bin, true
            ws.config.set "USE_PYTHON_VENV", venv, true unless venv.nil?
            ws.config.set "USE_PYTHON_UV", use_uv, true
        end

        def shim(name)
            File.join(ws.dot_autoproj_dir, "bin", name)
        end

        describe "venv_enabled?" do
            it "is enabled if both USE_PYTHON and USE_PYTHON_VENV are set" do
                configure_python
                assert Python.venv_enabled?(ws: ws)
                refute Python.uv_enabled?(ws: ws)
            end

            it "is disabled if USE_PYTHON is false" do
                configure_python
                ws.config.set "USE_PYTHON", false, true
                refute Python.venv_enabled?(ws: ws)
            end

            it "does not ask for undeclared or unvalidated options" do
                ws.config.declare "USE_PYTHON_VENV", "boolean", default: "yes"
                ws.config.set "USE_PYTHON", true, false
                flexmock(ws.config).should_receive(:configure).never
                refute Python.venv_enabled?(ws: ws)
            end
        end

        describe "externally_managed?" do
            it "detects the EXTERNALLY-MANAGED marker of the interpreter" do
                expected = Open3.capture2(
                    @python_bin, "-c",
                    "import os, sysconfig; print(os.path.isfile(os.path.join(" \
                    "sysconfig.get_path('stdlib'), 'EXTERNALLY-MANAGED')))"
                ).first.strip == "True"
                assert_equal expected, Python.externally_managed?(@python_bin)
            end

            it "returns false for a non-existent interpreter" do
                refute Python.externally_managed?("/does/not/exist")
            end
        end

        describe "setup_python_configuration_options" do
            it "enables the venv by default for externally managed interpreters" do
                ws.config.set "USE_PYTHON", true, true
                flexmock(Python).should_receive(:externally_managed?).and_return(true)
                Python.setup_python_configuration_options(ws: ws)
                assert ws.config.get("USE_PYTHON_VENV")
                assert ws.config.get("USE_PYTHON_UV")
                assert Python.venv_enabled?(ws: ws)
            end

            it "disables the venv by default for other interpreters" do
                ws.config.set "USE_PYTHON", true, true
                flexmock(Python).should_receive(:externally_managed?).and_return(false)
                Python.setup_python_configuration_options(ws: ws)
                refute ws.config.get("USE_PYTHON_VENV")
                refute ws.config.has_value_for?("USE_PYTHON_UV")
            end

            it "keeps the base interpreter as python_executable" do
                configure_python
                Python.setup_python_configuration_options(ws: ws)
                assert_equal @python_bin, ws.config.get("python_executable")
            end

            it "migrates the configuration of Rock's package set implementation" do
                configure_python
                venv = Python.venv_path(ws: ws)
                ws.config.set "python_executable", File.join(venv, "bin", "python3"), true
                ws.config.set "PYTHON_VENV_FOLDER", venv, true
                ws.config.set "PYTHON_VENV_INIT_EXECUTABLE", @python_bin, true
                Python.setup_python_configuration_options(ws: ws)
                assert_equal @python_bin, ws.config.get("python_executable")
                refute ws.config.has_value_for?("PYTHON_VENV_FOLDER")
                refute ws.config.has_value_for?("PYTHON_VENV_INIT_EXECUTABLE")
            end

            it "prints a hint when the venv gets disabled" do
                configure_python
                FileUtils.mkdir_p Python.venv_path(ws: ws)
                flexmock(ws.config).should_receive(:get).with("USE_PYTHON_VENV")
                                   .and_return(false)
                flexmock(ws.config).should_receive(:get).pass_thru
                messages = []
                flexmock(Autoproj).should_receive(:message)
                                  .and_return { |msg| messages << msg }
                Python.setup_python_configuration_options(ws: ws)
                assert(messages.any? { |m| m =~ /can be deleted/ })
            end

            it "does not print the hint if the setting did not change" do
                configure_python
                flexmock(Autoproj).should_receive(:message).never
                Python.setup_python_configuration_options(ws: ws)
            end
        end

        describe "activate_python" do
            it "points the shims to the venv and fails with a hint if it is missing" do
                configure_python
                Python.activate_python(ws: ws)
                assert_match(/#{Regexp.quote(Python.venv_python(ws: ws))}/,
                             File.read(shim("python")))
                out, status = Open3.capture2e(shim("python"), "--version")
                assert_equal 127, status.exitstatus
                assert_match(/autoproj osdeps/, out)
            end

            it "points the shims to the system python if the venv is disabled" do
                configure_python(venv: false)
                Python.activate_python(ws: ws)
                assert_match(/exec #{Regexp.quote(@python_bin)}/,
                             File.read(shim("python")))
                assert_match(/exec #{Regexp.quote(@python_bin)} -m pip/,
                             File.read(shim("pip")))
            end

            it "sets up the environment for the venv" do
                configure_python
                Python.activate_python(ws: ws)
                env = ws.env.environment
                assert_equal [Python.venv_path(ws: ws)], env["VIRTUAL_ENV"]
                assert_equal ["1"], env["PYTHONNOUSERSITE"]
                assert_nil env["PYTHONUSERBASE"]
                assert_includes env["PATH"], File.join(Python.venv_path(ws: ws), "bin")
            end

            it "switches the environment back if the venv gets disabled" do
                configure_python
                Python.activate_python(ws: ws)
                ws.config.set "USE_PYTHON_VENV", false, true
                Python.activate_python(ws: ws)
                env = ws.env.environment
                refute env.key?("VIRTUAL_ENV")
                refute env.key?("PYTHONNOUSERSITE")
                assert_equal [Python.pip_home(ws: ws)], env["PYTHONUSERBASE"]
                refute_includes env["PATH"], File.join(Python.venv_path(ws: ws), "bin")
            end
        end

        describe "venv lifecycle" do
            before do
                configure_python
                Python.activate_python(ws: ws)
            end

            def write_fake_venv(version)
                bin = File.join(Python.venv_path(ws: ws), "bin")
                FileUtils.mkdir_p bin
                FileUtils.ln_s @python_bin, File.join(bin, "python")
                File.write(File.join(Python.venv_path(ws: ws), "pyvenv.cfg"),
                           "home = /usr/bin\nversion = #{version}\n")
            end

            it "accepts a venv matching the configured python version" do
                write_fake_venv("#{ws.config.get('python_version')}.42")
                assert Python.venv_valid?(ws: ws)
                refute Python.prepare_venv(ws: ws)
                assert File.directory?(Python.venv_path(ws: ws))
            end

            it "recreates a venv created with another python version" do
                write_fake_venv("2.7.18")
                refute Python.venv_valid?(ws: ws)
                flexmock(Autoproj).should_receive(:message).with(/recreating/).once
                assert Python.prepare_venv(ws: ws)
                refute File.exist?(Python.venv_path(ws: ws))
            end

            it "recreates a venv whose interpreter is gone" do
                write_fake_venv(ws.config.get("python_version"))
                FileUtils.rm File.join(Python.venv_path(ws: ws), "bin", "python")
                refute Python.venv_valid?(ws: ws)
            end

            it "returns the commands to create a missing venv" do
                cmdlines = Python.venv_setup_cmdlines(ws: ws)
                python = Python.venv_python(ws: ws)
                assert_equal [[@python_bin, "-m", "venv", "--system-site-packages",
                               Python.venv_path(ws: ws)],
                              [python, "-m", "pip", "install", "--upgrade", "pip"]],
                             cmdlines
            end

            it "installs uv into the venv if enabled" do
                write_fake_venv(ws.config.get("python_version"))
                ws.config.set "USE_PYTHON_UV", true, true
                assert_equal [[Python.venv_python(ws: ws), "-m", "pip", "install", "uv"]],
                             Python.venv_setup_cmdlines(ws: ws)
                FileUtils.touch Python.venv_uv(ws: ws)
                FileUtils.chmod 0o755, Python.venv_uv(ws: ws)
                assert_empty Python.venv_setup_cmdlines(ws: ws)
            end

            it "creates a working venv" do
                skip "long test" if skip_long_tests?

                cmdline = Python.venv_setup_cmdlines(ws: ws).first
                _, status = Open3.capture2e(*cmdline)
                skip "cannot create venvs (python3-venv missing?)" unless status.success?

                assert Python.venv_valid?(ws: ws)
                out, status = Open3.capture2e(
                    shim("python"), "-c", "import sys; print(sys.prefix)"
                )
                assert status.success?, out
                assert_equal File.realpath(Python.venv_path(ws: ws)),
                             File.realpath(out.strip)
            end
        end

        # Installs packages from PyPI, enable with AUTOPROJ_TEST_NETWORK=1
        describe "end-to-end installation" do
            before do
                skip "requires network access" unless ENV["AUTOPROJ_TEST_NETWORK"] == "1"
                skip "long test" if skip_long_tests?
            end

            def assert_installed
                out, status = Open3.capture2e(
                    shim("python"), "-c", "import pip_install_test"
                )
                assert status.success?, out
            end

            [false, true].each do |uv|
                it "creates the venv and installs into it (uv: #{uv})" do
                    configure_python(use_uv: uv)
                    pip_manager = PackageManagers::PipManager.new(ws)
                    pip_manager.install(["pip-install-test"])
                    assert_installed
                    assert_equal uv, File.executable?(Python.venv_uv(ws: ws))

                    # The venv must be safe to delete
                    FileUtils.rm_rf Python.venv_path(ws: ws)
                    pip_manager.install(["pip-install-test"])
                    assert_installed
                end
            end
        end
    end
end
