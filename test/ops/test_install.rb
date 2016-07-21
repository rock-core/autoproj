require 'autoproj/test'
require 'autoproj/ops/configuration'

describe Autoproj::Ops::Install do
    before do
        @tempdirs ||= Array.new
    end
    after do
        @tempdirs.each do |dir|
            FileUtils.rm_rf dir
        end
    end

    def make_tmpdir
        dir = Dir.mktmpdir
        @tempdirs << dir
        dir
    end

    def scripts_dir
        File.expand_path(File.join('install'), File.dirname(__FILE__))
    end

    def find_gem_dir(gem_name)
        Bundler.definition.specs.each do |spec|
            if spec.name == gem_name
                return spec
            end
        end
        nil
    end

    def invoke_test_script(name, *arguments, dir: nil, seed_config: File.join(scripts_dir, 'seed-config.yml'), env: Hash.new, display_output: false, copy_from: nil)
        package_base_dir = File.expand_path(File.join('..', '..'), File.dirname(__FILE__))
        script = File.expand_path(name, scripts_dir)
        if !File.file?(script)
            raise ArgumentError, "no test script #{name}.sh in #{test_dir}"
        end

        if seed_config
            arguments << '--seed-config' << seed_config
        end

        dir ||= make_tmpdir
        if ENV['USE_AUTOPROJ_FROM_RUBYGEMS'] != '1'
            autoproj_dir  = find_gem_dir('autoproj').full_gem_path
            autobuild_dir = find_gem_dir('autobuild').full_gem_path
            File.open(File.join(dir, 'Gemfile-dev'), 'w') do |io|
                io.puts "source \"http://localhost:8808\""
                io.puts "gem 'autoproj', path: '#{autoproj_dir}'"
                io.puts "gem 'autobuild', path: '#{autobuild_dir}'"
            end
            arguments << "--gemfile" << File.join(dir, "Gemfile-dev") << "--gem-source" << "http://localhost:8808"
        end

        if copy_from
            test_workspace = File.expand_path(copy_from, scripts_dir)
            if File.directory?(test_workspace)
                FileUtils.cp_r test_workspace, dir
                dir = File.join(dir, File.basename(test_workspace))
            end
        end
        result = nil
        stdout, stderr = capture_subprocess_io do
            result = Bundler.clean_system(
                Hash['PACKAGE_BASE_DIR' => package_base_dir, 'RUBY' => Gem.ruby].merge(env),
                script, *arguments, chdir: dir, in: :close)
        end

        if !result
            puts stdout
            puts stderr
            flunk("test script #{name} failed")
        elsif display_output
            puts stdout
            puts stderr
        end
        return dir, stdout, stderr
    end

    describe "install" do
        def find_bundled_gem_path(bundler, gem_name, gemfile)
            out_r, out_w = IO.pipe
            result = Bundler.clean_system(
                Hash['BUNDLE_GEMFILE' => gemfile],
                bundler, 'show', gem_name,
                out: out_w)
            out_w.close
            output = out_r.read.chomp
            assert result, "#{output}"
            output
        end

        def workspace_env(varname)
            _, stdout, _ = invoke_test_script 'display-env.sh', varname, dir: install_dir
            stdout.chomp
        end

        describe "default shared gems location" do
            attr_reader :shared_gem_home, :shared_dir, :install_dir
            before do
                @shared_dir = Dir.mktmpdir
                @shared_gem_home = File.join(shared_dir, '.autoproj', 'gems', Autoproj::Configuration.gems_path_suffix)
                @install_dir, _ = invoke_test_script 'install.sh', env: Hash['HOME' => shared_dir]
            end

            it "saves a shim to the installed bundler" do
                shim_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')
                content = File.read(shim_path)
                assert_match /exec .*#{File.join(shared_gem_home, 'bin', 'bundler')}/, content
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
                @shared_dir = Dir.mktmpdir
                @shared_gem_home = File.join(shared_dir, Autoproj::Configuration.gems_path_suffix)
                @install_dir, _ = invoke_test_script 'install.sh',
                    "--shared-gems=#{shared_dir}"
            end

            it "saves a shim to the installed bundler" do
                shim_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')
                content = File.read(shim_path)
                assert_match /exec .*#{File.join(shared_gem_home, 'bin', 'bundler')}/, content
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
                assert_match /exec .*#{File.join(autoproj_gem_home, 'bin', 'bundler')}/, content
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
    end

    describe "upgrade from v1" do
        attr_reader :install_dir
        before do
            shared_gems = Dir.mktmpdir
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

