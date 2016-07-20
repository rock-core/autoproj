require 'autoproj/test'
require 'autoproj/ops/configuration'

describe Autoproj::Ops::Install do
    before do
        @tempdirs = Array.new
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

    def invoke_test_script(name, *arguments, dir: nil, seed_config: File.join(scripts_dir, 'seed-config.yml'))
        package_base_dir = File.expand_path(File.join('..', '..'), File.dirname(__FILE__))
        script = File.join(scripts_dir, "#{name}.sh")
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
            arguments << "--gemfile" << File.join(dir, "Gemfile-dev")
        end

        test_workspace = File.join(scripts_dir, name)
        if File.directory?(test_workspace)
            FileUtils.cp_r test_workspace, dir
            dir = File.join(dir, name)
        end
        if !Bundler.clean_system(Hash['PACKAGE_BASE_DIR' => package_base_dir, 'RUBY' => Gem.ruby], script, *arguments, chdir: dir, in: :close)
            flunk("test script #{name} failed")
        end
        return dir
    end

    describe "install" do
        it "successfully installs autoproj" do
            invoke_test_script 'install'
        end
        it "installs bundler if it is not already installed" do
            bundler_dir = make_tmpdir
            invoke_test_script 'install', "--private-bundler=#{bundler_dir}"
            assert File.exist?(File.join(bundler_dir, 'bin', 'bundler'))
        end
        it "saves a shim to the installed bundler" do
            bundler_dir = make_tmpdir
            install_dir = invoke_test_script 'install', "--private-bundler=#{bundler_dir}"
            content = File.read(File.join(install_dir, '.autoproj', 'bin', 'bundler'))
            assert_match /exec .*#{bundler_dir}\/bin\/bundler/, content
        end
        it "adds the bundler dir to the GEM_PATH" do
            bundler_dir = make_tmpdir
            install_dir = invoke_test_script 'install', "--private-bundler=#{bundler_dir}"
            env_sh = File.read(File.join(install_dir, 'env.sh'))
            assert env_sh.split("\n").include?("GEM_PATH=\"#{bundler_dir}\"")
        end

        def find_bundled_gem_path(bundler, gem_name, gemfile)
            out_r, out_w = IO.pipe
            result = Bundler.clean_system(
                Hash['BUNDLE_GEMFILE' => gemfile],
                bundler, 'show', gem_name,
                out: out_w)
            out_w.close
            output = out_r.read
            assert result, "#{output}"
            output
        end

        it "accepts installing the autoproj gems in a dedicated directory" do
            bundler_dir  = make_tmpdir
            autoproj_dir = make_tmpdir
            install_dir  = invoke_test_script 'install', "--private-bundler=#{bundler_dir}", "--private-autoproj=#{autoproj_dir}"

            autoproj_gemfile = File.join(install_dir, '.autoproj', 'autoproj', 'Gemfile')
            utilrb_gem = find_bundled_gem_path(File.join(bundler_dir, 'bin', 'bundler'), 'utilrb', autoproj_gemfile)
            assert utilrb_gem.start_with?(autoproj_dir)
        end

        it "can install all gems in the .autoproj folder" do
            install_dir  = invoke_test_script 'install', "--private"
            bundler_path = File.join(install_dir, '.autoproj', 'bin', 'bundler')

            autoproj_gemfile = File.join(install_dir, '.autoproj', 'autoproj', 'Gemfile')
            utilrb_gem = find_bundled_gem_path(bundler_path, 'utilrb', autoproj_gemfile)
            assert utilrb_gem.start_with?(File.join(install_dir, '.autoproj', 'autoproj'))
        end
    end

    describe "upgrade from v1" do
        it "saves the original v1 env.sh" do
            dir = invoke_test_script 'upgrade_from_v1'
            assert_equal "UPGRADE_FROM_V1=1", File.read(File.join(dir, 'env.sh-autoproj-v1')).strip
        end
        it "merges the existing v1 configuration" do
            dir = invoke_test_script 'upgrade_from_v1'
            new_config = YAML.load(File.read(File.join(dir, '.autoproj', 'config.yml')))
            assert_equal true, new_config['test_v1_config']
        end
    end
end

