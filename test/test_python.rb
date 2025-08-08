# frozen_string_literal: true

require "autoproj/python"
require "autoproj/test"

module Autoproj
    module Python
        describe "activate_python" do
            before do
                @python_bin = guess_python_bin
                flunk("cannot find a python executable") unless @python_bin

                @pkg = Autobuild::Package.new("#{self.class.name}-#{Process.pid}-#{rand}")
                @ws = ws_create
                @ws.os_package_resolver.load_default
                flexmock(@pkg)
                @pkg.prefix = File.join(@ws.prefix_dir, "foo")
                @env = flexmock(base: Autobuild::Environment)

                @test_python = File.join(Dir.tmpdir, "test-python")
                File.symlink(@python_bin, @test_python) unless File.exist?(@test_python)
            end
            after do
                FileUtils.rm(@test_python) unless File.exist?(@test_python)
            end

            it "does get the python version" do
                assert_raises { Autoproj::Python.get_python_version("no-existing-file") }
                assert_raises { Autoproj::Python.get_python_version(__FILE__) }

                refute_equal "", Autoproj::Python.get_python_version(@python_bin)
            end

            it "does validate the python version" do
                version, valid = Autoproj::Python.validate_python_version(@python_bin, nil)
                assert_match(/[0-9]+\.[0-9]+/, version)
                assert(valid)

                version_a, valid = Autoproj::Python.validate_python_version(@python_bin, ">2.0")
                assert_equal(version, version_a)
                assert(valid)

                version_a, valid = Autoproj::Python.validate_python_version(@python_bin, "<100.0")
                assert_equal(version, version_a)
                assert(valid)

                version_a, valid = Autoproj::Python.validate_python_version(@python_bin, ">100.0")
                assert_equal(version, version_a)
                refute valid
            end

            it "does find python" do
                assert_raises { Autoproj::Python.find_python(ws: @ws, version: ">100.0") }
                python_bin, version = Autoproj::Python.find_python(ws: @ws, version: "<100.0")
                assert_equal(@python_bin, python_bin)
                assert(version =~ /[0-9]+\.[0-9]+/)

                # Python3 has higher priority, so should be picked
                assert(version =~ /3.[0-9]+/)
            end

            it "custom resolve python" do
                python_bin_resolved, _version_resolved = Autoproj::Python.custom_resolve_python(bin: @test_python)
                assert(python_bin_resolved)
                assert_raises do
                    Autoproj::Python.custom_resolve_python(bin: @test_python,
                                                           version: ">100.0")
                end

                assert_raises { Autoproj::Python.custom_resolve_python(bin: "no-existing-python") }

                _python_bin, version = Autoproj::Python.find_python(ws: @ws)
                @ws.config.set("python_executable", @test_python)
                @ws.config.set("python_version", version)

                python_bin_resolved, version_resolved = Autoproj::Python.resolve_python(ws: @ws)
                assert(python_bin_resolved == @test_python)
                assert(version_resolved == version)

                assert_raises { Autoproj::Python.resolve_python(ws: @ws, version: ">100.0") }

                @ws.config.set("python_executable", nil)
                @ws.config.set("python_version", nil)
            end

            it "does update the python path" do
                @ws.config.set("USE_PYTHON", true)
                bin, version, sitelib_path = Autoproj::Python.activate_python_path(@pkg, ws: @ws)

                python_bin_name = File.basename(bin)
                python_bin = `which #{python_bin_name}`.strip
                assert($CHILD_STATUS == 0, "This test requires python to be available on your"\
                                           " system, so please install before running this test")

                assert(python_bin == bin, "Python bin #{python_bin} not equal to #{bin}")
                assert(version == Autoproj::Python.get_python_version(python_bin))
                assert(sitelib_path == File.join(@pkg.prefix, "lib", "python#{version}", "site-packages"))

                found_path = false
                path_pattern = File.join(@pkg.prefix, "lib", "python.*", "site-packages")

                @env.should_receive(:add_path)
                op = @pkg.apply_env(@env).first

                assert(op.type == :add_path)
                assert(op.name == "PYTHONPATH")
                # rubocop:disable Style/HashEachMethods
                op.values.each do |p|
                    found_path = true if p =~ /#{path_pattern}/
                end
                # rubocop:enable Style/HashEachMethods
                assert(found_path)
                assert(!@ws.config.has_value_for?("python_executable"))
                assert(!@ws.config.has_value_for?("python_version"))

                assert_raises { Autoproj::Python.activate_python_path(@pkg, ws: @ws, version: ">100.0") }

                Autobuild.programs["python"] = "no-existing-executable"
                assert_raises { Autoproj::Python.activate_python_path(@pkg, ws: @ws, version: ">100.0") }
                Autobuild.programs["python"] = nil
            end

            it "does not update python path" do
                @ws.config.reset
                @ws.config.set("interactive", false)
                @ws.config.set("USE_PYTHON", false)

                pkg = flexmock("testpkg")
                prefix = File.join(@ws.prefix_dir, "testpkg")
                pkg.should_receive(:prefix).and_return(prefix)
                assert(!@ws.config.has_value_for?("python_executable"))
                assert(!@ws.config.has_value_for?("python_version"))

                bin, version, path = Autoproj::Python.activate_python_path(pkg, ws: @ws)
                assert(!(bin || version || path))
            end

            it "does activate_python" do
                Autoproj::Python.activate_python(ws: @ws)
                assert(@ws.config.has_value_for?("python_executable"))
                assert(@ws.config.has_value_for?("python_version"))

                python_bin = File.join(@ws.dot_autoproj_dir, "bin", "python")
                assert(File.exist?(python_bin))
                python_version = Autoproj::Python.get_python_version(python_bin)
                assert(python_version == @ws.config.get("python_version"))

                pip_bin = File.join(@ws.dot_autoproj_dir, "bin", "pip")
                assert(File.exist?(pip_bin))
                pip_version = Autoproj::Python.get_pip_version(pip_bin)
                expected_pip_version = `#{python_bin} -c "import pip; print(pip.__version__)"`.strip
                assert(pip_version == expected_pip_version)
            end

            it "does setup python" do
                @ws.config.reset
                @ws.config.set("interactive", false)
                @ws.config.set("USE_PYTHON", true)
                @ws.config.set("osdeps_mode", "all")
                Autoproj::Python.setup_python_configuration_options(ws: @ws)
                assert(@ws.config.get("USE_PYTHON"))
                assert(@ws.config.get("python_executable"))
                assert(@ws.config.get("python_version"))

                @ws.config.reset
                @ws.config.set("interactive", false)
                Autoproj::Python.setup_python_configuration_options(ws: @ws)
                if Autoproj::VERSION > "2.11.0"
                    assert(!@ws.config.get("USE_PYTHON"))
                else
                    assert(@ws.config.get("USE_PYTHON") == "no")
                end
                assert(!@ws.config.has_value_for?("python_executable"))
                assert(!@ws.config.has_value_for?("python_version"))
            end

            def guess_python_bin
                env = Autobuild::Environment.new
                env.isolate
                env.find_in_path("python3") || env.find_in_path("python")
            end
        end
    end
end
