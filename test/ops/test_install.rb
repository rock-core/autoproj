require 'autoproj/test'
require 'autoproj/ops/configuration'

module Autoproj
    module Ops
        describe Install do
            before do
                prepare_fixture_gem_home
                start_gem_server
            end

            it "installs fine when using the default gem source" do
                shared_dir = make_tmpdir
                autoproj_dir  = find_gem_dir('autoproj').full_gem_path
                autobuild_dir = find_gem_dir('autobuild').full_gem_path
                gemfile_source = "source \"https://rubygems.org\"
gem 'autoproj', path: '#{autoproj_dir}'
gem 'autobuild', path: '#{autobuild_dir}'"

                invoke_test_script 'install.sh', use_autoproj_from_rubygems: true, env: Hash['HOME' => shared_dir],
                    gemfile_source: gemfile_source
            end

            describe "default shared gems location" do
                attr_reader :shared_gem_home, :shared_dir, :install_dir
                before do
                    @shared_dir = make_tmpdir
                    @shared_gem_home = File.join(shared_dir, '.autoproj', 'gems', Autoproj::Configuration.gems_path_suffix)
                    @install_dir, _ = invoke_test_script 'install.sh', env: Hash['HOME' => shared_dir]
                end

                it "saves a shim to the installed bundler" do
                    shim_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')
                    assert File.file?(shim_path)
                    stdout, stderr = capture_subprocess_io do
                        if !Bundler.clean_system(shim_path, 'show', 'bundler')
                            flunk("could not run the bundler shim")
                        end
                    end
                    assert stdout.start_with?(shared_gem_home), "expected #{stdout} to start with #{shared_gem_home}"
                end

                it "sets the environment so that the shared bundler is found" do
                    shim_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')
                    _, stdout, _ = invoke_test_script 'bundler-path.sh', dir: install_dir, chdir: File.join(install_dir, '.autoproj')
                    bundler_bin_path, bundler_gem_path =
                        stdout.chomp.split("\n")
                    assert_equal bundler_bin_path, shim_path
                    assert bundler_gem_path.start_with?(shared_gem_home)
                end

                it "sets the environment to point RubyGems to the shared location" do
                    assert_equal shared_gem_home, workspace_env('GEM_HOME')
                    assert_equal '', workspace_env('GEM_PATH')
                end

                it "does not add the shared locations' bin to PATH" do
                    refute workspace_env('PATH').split(":").include?(shared_gem_home)
                end

                it "installs all gems in the shared folder" do
                    bundler_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')
                    autoproj_gemfile = File.join(install_dir, '.autoproj', 'Gemfile')
                    utilrb_gem = find_bundled_gem_path(bundler_path, 'utilrb', autoproj_gemfile)
                    assert utilrb_gem.start_with?(shared_gem_home)
                end
            end

            describe "explicit shared location" do
                attr_reader :shared_gem_home, :install_dir, :shared_dir
                before do
                    @shared_dir = make_tmpdir
                    @shared_gem_home = File.join(shared_dir, Autoproj::Configuration.gems_path_suffix)
                    @install_dir, _ = invoke_test_script 'install.sh',
                        "--gems-path=#{shared_dir}"
                end

                it "saves a shim to the installed bundler" do
                    shim_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')
                    assert File.file?(shim_path)
                    stdout, stderr = capture_subprocess_io do
                        if !Bundler.clean_system(shim_path, 'show', 'bundler')
                            flunk("could not run the bundler shim")
                        end
                    end
                    assert stdout.start_with?(shared_gem_home), "expected #{stdout} to start with #{shared_gem_home}"
                end

                it "sets the environment so that the shared bundler is found" do
                    shim_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')
                    _, stdout, _ = invoke_test_script 'bundler-path.sh', dir: install_dir, chdir: File.join(install_dir, '.autoproj')

                    bundler_bin_path, bundler_gem_path =
                        stdout.chomp.split("\n")
                    assert_equal bundler_bin_path, shim_path
                    assert bundler_gem_path.start_with?(shared_gem_home)
                end

                it "sets the environment to point RubyGems to the shared location" do
                    assert_equal shared_gem_home, workspace_env('GEM_HOME')
                    assert_equal '', workspace_env('GEM_PATH')
                end

                it "does not add the shared locations' bin to PATH" do
                    expected_path = File.join(shared_gem_home, 'bin')
                    refute workspace_env('PATH').split(":").include?(expected_path)
                end

                it "installs all gems in the shared folder" do
                    bundler_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')
                    autoproj_gemfile = File.join(install_dir, '.autoproj', 'Gemfile')
                    utilrb_gem = find_bundled_gem_path(bundler_path, 'utilrb', autoproj_gemfile)
                    assert utilrb_gem.start_with?(shared_gem_home)
                end
            end

            describe "upgrade from v1" do
                attr_reader :install_dir
                before do
                    shared_gems = make_tmpdir
                    @install_dir, _ = invoke_test_script 'upgrade_from_v1.sh', "--gems-path=#{shared_gems}", copy_from: 'upgrade_from_v1'
                end
                it "saves the original v1 env.sh" do
                    assert_equal "UPGRADE_FROM_V1=1", File.read(File.join(install_dir, 'env.sh-autoproj-v1')).strip
                end
                it "merges the existing v1 configuration" do
                    new_config = YAML.load(File.read(File.join(install_dir, '.autoproj', 'config.yml')))
                    assert_equal true, new_config['test_v1_config']
                end
            end
        end
    end
end

