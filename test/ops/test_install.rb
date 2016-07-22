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
                invoke_test_script 'install.sh', use_autoproj_from_rubygems: true, env: Hash['HOME' => shared_dir]
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
                    content = File.read(shim_path)
                    assert_match(/exec .*#{File.join(shared_gem_home, 'bin', 'bundler')}/, content)
                end

                it "sets the environment so that the shared bundler is found" do
                    shim_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')
                    _, stdout, _ = invoke_test_script 'bundler-path.sh', dir: install_dir
                    bundler_bin_path, bundler_gem_path =
                        stdout.chomp.split("\n")
                    assert_equal bundler_bin_path, shim_path
                    assert bundler_gem_path.start_with?(shared_gem_home)
                end

                it "sets the environment to point RubyGems to the shared location" do
                    assert_equal shared_gem_home, workspace_env('GEM_HOME')
                    assert_equal shared_gem_home, workspace_env('GEM_PATH')
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
                        "--shared-gems=#{shared_dir}"
                end

                it "saves a shim to the installed bundler" do
                    shim_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')
                    content = File.read(shim_path)
                    assert_match(/exec .*#{File.join(shared_gem_home, 'bin', 'bundler')}/, content)
                end

                it "sets the environment so that the shared bundler is found" do
                    shim_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')
                    _, stdout, _ = invoke_test_script 'bundler-path.sh', dir: install_dir
                    bundler_bin_path, bundler_gem_path =
                        stdout.chomp.split("\n")
                    assert_equal bundler_bin_path, shim_path
                    assert bundler_gem_path.start_with?(shared_gem_home)
                end

                it "sets the environment to point RubyGems to the shared location" do
                    assert_equal shared_gem_home, workspace_env('GEM_HOME')
                    assert_equal shared_gem_home, workspace_env('GEM_PATH')
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

            describe '--private' do
                attr_reader :install_dir, :dot_autoproj_dir, :autoproj_gem_home, :gems_home
                before do
                    @install_dir, _   = invoke_test_script 'install.sh', "--private"
                    @dot_autoproj_dir = Pathname.new(install_dir) + ".autoproj"
                    @autoproj_gem_home = dot_autoproj_dir + "gems" +
                        Autoproj::Configuration.gems_path_suffix
                    @gems_home         = Pathname.new(install_dir) + 'install' + "gems" +
                        Autoproj::Configuration.gems_path_suffix
                end

                it "resolves autoproj and its dependencies in the .autoproj gem folder" do
                    bundler_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')
                    autoproj_gemfile = File.join(install_dir, '.autoproj', 'Gemfile')
                    utilrb_gem = find_bundled_gem_path(bundler_path, 'utilrb', autoproj_gemfile)
                    assert utilrb_gem.start_with?(autoproj_gem_home.to_s)
                end

                it "saves a shim to the installed bundler" do
                    shim_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')
                    content = File.read(shim_path)
                    assert_match(/exec .*#{File.join(autoproj_gem_home, 'bin', 'bundler')}/, content)
                end

                it "sets the environment so that bundler is found" do
                    shim_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')
                    _, stdout, _ = invoke_test_script 'bundler-path.sh', dir: install_dir
                    bundler_bin_path, bundler_gem_path =
                        stdout.chomp.split("\n")
                    assert_equal bundler_bin_path, shim_path
                    assert bundler_gem_path.start_with?(autoproj_gem_home.to_s)
                end

                it "sets GEM_HOME to the gems location" do
                    assert_equal gems_home.to_s, workspace_env('GEM_HOME')
                end
                it "sets GEM_PATH to resolve autoproj and bundler's gem home" do
                    assert_equal autoproj_gem_home.to_s, workspace_env('GEM_PATH')
                end

                it "does not add the bundler and autoproj gems_home' bin to PATH" do
                    path = workspace_env('PATH')
                    expected_path = File.join(autoproj_gem_home, 'bin')
                    refute path.include?(expected_path)
                end

                it "places the shims path before the gems bin" do
                    path = workspace_env('PATH')
                    shims_index = path.index(File.join(dot_autoproj_dir, 'bin'))
                    gems_bin         = Pathname.new(install_dir) + 'install' + "gems"
                    gems_index  = path.index(gems_bin.to_s)
                    assert(shims_index < gems_index)
                end

                it "does add the gems_home bin to PATH" do
                    path = workspace_env('PATH')
                    gems_bin         = Pathname.new(install_dir) + 'install' + "gems"
                    assert path.include?(gems_bin.to_s)
                end
            end

            describe "upgrade from v1" do
                attr_reader :install_dir
                before do
                    shared_gems = make_tmpdir
                    @install_dir, _ = invoke_test_script 'upgrade_from_v1.sh', "--shared-gems", shared_gems, copy_from: 'upgrade_from_v1'
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

