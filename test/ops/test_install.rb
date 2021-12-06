require "autoproj/test"
require "autoproj/ops/configuration"

module Autoproj
    module Ops
        describe Install do
            before do
                skip "long test" if skip_long_tests?
            end

            it "installs autoproj" do
                invoke_test_script "install.sh"
            end

            it "may install non-interactively" do
                invoke_test_script "install.sh",
                                   interactive: false,
                                   seed_config: nil
            end

            it "the non-interactive installs also ignore non-empty directories" do
                install_dir = make_tmpdir
                FileUtils.touch File.join(install_dir, "somefile")
                invoke_test_script "install.sh",
                                   dir: install_dir,
                                   interactive: false,
                                   seed_config: nil
            end

            describe "running autoproj_install in an existing workspace" do
                before do
                    @install_dir = make_tmpdir
                    @config_yml = File.join(@install_dir, ".autoproj", "config.yml")
                    FileUtils.mkdir_p File.dirname(@config_yml)
                    File.open(@config_yml, "w") { |io| YAML.dump({ "test" => "flag" }, io) }
                end

                it "seeds the config with the workspace's" do
                    invoke_test_script "install.sh", dir: @install_dir
                    assert_equal "flag", YAML.safe_load(File.read(@config_yml))["test"]
                end

                it "lets the user override the existing workspace configuration with its own seed" do
                    seed_config_yml = File.join(make_tmpdir, "config.yml")
                    File.open(seed_config_yml, "w") do |io|
                        YAML.dump({ "test" => "something else" }, io)
                    end
                    invoke_test_script "install.sh", "--seed-config", seed_config_yml,
                                       dir: @install_dir
                    assert_equal "something else",
                                 YAML.safe_load(File.read(@config_yml))["test"]
                end

                it "lets the user disable the automatic seeding" do
                    invoke_test_script "install.sh", "--no-seed-config", dir: @install_dir
                    refute YAML.safe_load(File.read(@config_yml)).key?("test")
                end
            end

            describe "npython shims" do
                attr_reader :install_dir, :shared_dir, :python_shim, :pip_shim

                before do
                    @install_dir = make_tmpdir
                    @shared_dir = make_tmpdir

                    FileUtils.mkdir_p File.join(install_dir, ".autoproj", "bin")
                    @python_shim = File.join(install_dir, ".autoproj", "bin", "python")
                    @pip_shim = File.join(install_dir, ".autoproj", "bin", "pip")

                    File.open(python_shim, "w") { |f| f.write("foobar") }
                    File.open(pip_shim, "w") { |f| f.write("foobar") }

                    @install_dir, = invoke_test_script(
                        "install.sh", dir: install_dir, env: { "HOME" => shared_dir }
                    )
                end

                it "does not overwrite python shims" do
                    assert_equal "foobar", File.open(python_shim).read
                    assert_equal "foobar", File.open(pip_shim).read
                end
            end

            describe "default shared gems location" do
                attr_reader :shared_gem_home, :shared_dir, :install_dir

                before do
                    @shared_dir = make_tmpdir
                    @shared_gem_home = File.join(
                        shared_dir, ".local", "share", "autoproj",
                        "gems", Autoproj::Configuration.gems_path_suffix
                    )
                    @install_dir, = invoke_test_script(
                        "install.sh", env: { "HOME" => shared_dir }
                    )
                end

                it "saves a shim to the installed bundler" do
                    shim_path = File.join(install_dir, ".autoproj", "bin", "bundle")
                    assert File.file?(shim_path)
                    stdout, _stderr = capture_subprocess_io do
                        unless Autoproj.bundler_unbundled_system(shim_path, "show", "bundler")
                            flunk("could not run the bundler shim")
                        end
                    end
                    assert stdout.start_with?(shared_gem_home),
                           "expected #{stdout} to start with #{shared_gem_home}"
                end

                it "removes non-autoproj and non-bundler shims from the shim folder" do
                    shim_path = File.join(install_dir, ".autoproj", "bin")
                    refute File.file?(File.join(shim_path, "rake")),
                           "rake is still present in the shim folder"
                    refute File.file?(File.join(shim_path, "thor")),
                           "thor is still present in the shim folder"
                end

                it "sets the environment so that the shared bundler is found" do
                    shim_path = File.join(install_dir, ".autoproj", "bin", "bundle")
                    _, stdout, = invoke_test_script "bundler-path.sh",
                                                    dir: install_dir,
                                                    chdir: File.join(install_dir, ".autoproj")
                    bundler_bin_path, bundler_gem_path =
                        stdout.chomp.split("\n")
                    assert_equal bundler_bin_path, shim_path
                    assert bundler_gem_path.start_with?(shared_gem_home)
                end

                it "sets the environment to point RubyGems to the shared location" do
                    assert_equal shared_gem_home, workspace_env(@install_dir, "GEM_HOME")
                    assert_equal "", workspace_env(@install_dir, "GEM_PATH")
                end

                it "does not add the shared locations' bin to PATH" do
                    refute workspace_env(@install_dir, "PATH").split(":").include?(shared_gem_home)
                end

                it "installs all gems in the shared folder" do
                    bundler_path = File.join(install_dir, ".autoproj", "bin", "bundle")
                    autoproj_gemfile = File.join(install_dir, ".autoproj", "Gemfile")
                    utilrb_gem = find_bundled_gem_path(
                        bundler_path, "utilrb", autoproj_gemfile
                    )
                    assert utilrb_gem.start_with?(shared_gem_home)
                end
            end

            describe "explicit shared location" do
                attr_reader :shared_gem_home, :install_dir, :shared_dir

                before do
                    @shared_dir = make_tmpdir
                    @shared_gem_home =
                        File.join(shared_dir, Autoproj::Configuration.gems_path_suffix)
                    @install_dir, =
                        invoke_test_script("install.sh", "--gems-path=#{shared_dir}")
                end

                it "saves a shim to the installed bundler" do
                    shim_path = File.join(install_dir, ".autoproj", "bin", "bundle")
                    assert File.file?(shim_path)
                    stdout, _stderr = capture_subprocess_io do
                        unless Autoproj.bundler_unbundled_system(shim_path, "show", "bundler")
                            flunk("could not run the bundler shim")
                        end
                    end
                    assert stdout.start_with?(shared_gem_home), "expected #{stdout} to start with #{shared_gem_home}"
                end

                it "removes non-autoproj and non-bundler shims from the shim folder" do
                    shim_path = File.join(install_dir, ".autoproj", "bin")
                    refute File.file?(File.join(shim_path, "rake")),
                           "rake is still present in the shim folder"
                    refute File.file?(File.join(shim_path, "thor")),
                           "thor is still present in the shim folder"
                end

                it "sets the environment so that the shared bundler is found" do
                    shim_path = File.join(install_dir, ".autoproj", "bin", "bundle")
                    _, stdout, = invoke_test_script "bundler-path.sh",
                                                    dir: install_dir,
                                                    chdir: File.join(install_dir, ".autoproj")

                    bundler_bin_path, bundler_gem_path =
                        stdout.chomp.split("\n")
                    assert_equal bundler_bin_path, shim_path
                    assert bundler_gem_path.start_with?(shared_gem_home)
                end

                it "sets the environment to point RubyGems to the shared location" do
                    assert_equal shared_gem_home, workspace_env(@install_dir, "GEM_HOME")
                    assert_equal "", workspace_env(@install_dir, "GEM_PATH")
                end

                it "does not add the shared locations' bin to PATH" do
                    expected_path = File.join(shared_gem_home, "bin")
                    refute_includes workspace_env(@install_dir, "PATH").split(":"), expected_path
                end

                it "installs all gems in the shared folder" do
                    bundler_path = File.join(install_dir, ".autoproj", "bin", "bundle")
                    autoproj_gemfile = File.join(install_dir, ".autoproj", "Gemfile")
                    utilrb_gem = find_bundled_gem_path(
                        bundler_path, "utilrb", autoproj_gemfile
                    )
                    assert utilrb_gem.start_with?(shared_gem_home)
                end
            end

            describe "upgrade from v1" do
                attr_reader :install_dir

                before do
                    shared_gems = make_tmpdir
                    @install_dir, = invoke_test_script "upgrade_from_v1.sh", "--gems-path=#{shared_gems}", copy_from: "upgrade_from_v1"
                end
                it "saves the original v1 env.sh" do
                    assert_equal "UPGRADE_FROM_V1=1", File.read(File.join(install_dir, "env.sh-autoproj-v1")).strip
                end
                it "merges the existing v1 configuration" do
                    new_config = YAML.safe_load(File.read(File.join(install_dir, ".autoproj", "config.yml")))
                    assert_equal true, new_config["test_v1_config"]
                end
            end

            describe "bundler versioning" do
                it "picks a specific bundler version as passed in the seed config" do
                    seed_config_path = File.join(make_tmpdir, "config.yml")
                    File.open(seed_config_path, "w") do |io|
                        YAML.dump({ "bundler_version" => "2.0.1" }, io)
                    end

                    dir, = invoke_test_script(
                        "install.sh", "--seed-config", seed_config_path
                    )
                    assert_match(/2.0.1/, `#{dir}/.autoproj/bin/bundle --version`.strip)
                end

                it "picks a specific bundler version as passed on the command line" do
                    dir, = invoke_test_script("install.sh", "--bundler-version", "2.0.1")
                    assert_match(/2.0.1/, `#{dir}/.autoproj/bin/bundle --version`.strip)
                end

                it "pins the install to the selected bundler version" do
                    dir, = invoke_test_script("install.sh", "--bundler-version", "2.0.1")
                    `#{dir}/.autoproj/bin/autoproj update`
                    assert_match(/2.0.1/, `#{dir}/.autoproj/bin/bundle --version`.strip)
                end

                it "can pin a bundler version on an existing bootstrap" do
                    dir, = invoke_test_script("install.sh")
                    refute_match(/2.0.1/, `#{dir}/.autoproj/bin/bundle --version`.strip)
                    dir, = invoke_test_script("install.sh", "--bundler-version", "2.0.1")
                    assert_match(/2.0.1/, `#{dir}/.autoproj/bin/bundle --version`.strip)
                end

                it "can unpin a bundler version after the bootstrap" do
                    dir, = invoke_test_script("install.sh", "--bundler-version", "2.0.1")

                    config_yml = File.join(dir, ".autoproj", "config.yml")
                    config = YAML.safe_load(File.read(config_yml))
                    config.delete("bundler_version")
                    File.open(config_yml, "w") do |io|
                        YAML.dump(config, io)
                    end
                    `#{dir}/.autoproj/bin/autoproj update`
                    refute_match(/2.0.1/, `#{dir}/.autoproj/bin/bundle --version`.strip)
                end
            end
        end
    end
end
