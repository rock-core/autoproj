# simplecov must be loaded FIRST. Only the files required after it gets loaded
# will be profiled !!!
if ENV['TEST_ENABLE_COVERAGE'] == '1'
    begin
        require 'simplecov'
        SimpleCov.start do
            add_filter "/test/"
        end
    rescue LoadError
        require 'autoproj'
        Autoproj.warn "coverage is disabled because the 'simplecov' gem cannot be loaded"
    rescue Exception => e
        require 'autoproj'
        Autoproj.warn "coverage is disabled: #{e.message}"
    end
end

require 'minitest/autorun'
require 'autoproj'
require 'flexmock/minitest'
require 'minitest/spec'

if ENV['TEST_ENABLE_PRY'] != '0'
    begin
        require 'pry'
    rescue Exception
        Autoproj.warn "debugging is disabled because the 'pry' gem cannot be loaded"
    end
end

module Autoproj
    # This module is the common setup for all tests
    #
    # It should be included in the toplevel describe blocks
    #
    # @example
    #   require 'rubylib/test'
    #   describe Autoproj do
    #     include Autoproj::SelfTest
    #   end
    #
    module SelfTest
        attr_reader :ws

        def setup
            @gem_server_pid = nil
            @tmpdir = Array.new
            @ws = Workspace.new('/test/dir')
            ws.load_config
            Autoproj.workspace = ws

            super
        end

        def create_bootstrap
            dir = Dir.mktmpdir
            @tmpdir << dir
            require 'autoproj/ops/main_config_switcher'
            FileUtils.cp_r Ops::MainConfigSwitcher::MAIN_CONFIGURATION_TEMPLATE, File.join(dir, 'autoproj')
            Workspace.new(dir)
        end

        def make_tmpdir
            dir = Dir.mktmpdir
            @tmpdir << dir
            dir
        end

        def teardown
            super
            @tmpdir.each do |dir|
                FileUtils.remove_entry_secure dir
            end
            Autobuild::Package.clear

            if @gem_server_pid
                stop_gem_server
            end

            FileUtils.rm_rf fixture_gem_home
        end

        def scripts_dir
            File.expand_path(File.join('..', '..', 'test', 'scripts'), __dir__)
        end

        def find_gem_dir(gem_name)
            Bundler.definition.specs.each do |spec|
                if spec.name == gem_name
                    return spec
                end
            end
            nil
        end

        def autoproj_gemfile_to_local_checkout
            autoproj_dir  = find_gem_dir('autoproj').full_gem_path
            autobuild_dir = find_gem_dir('autobuild').full_gem_path
            "source \"http://localhost:8808\"
gem 'autoproj', path: '#{autoproj_dir}'
gem 'autobuild', path: '#{autobuild_dir}'
"
        end

        def invoke_test_script(name, *arguments,
                               dir: nil,
                               gemfile_source: nil,
                               use_autoproj_from_rubygems: (ENV['USE_AUTOPROJ_FROM_RUBYGEMS'] == '1'),
                               seed_config: File.join(scripts_dir, 'seed-config.yml'),
                               env: Hash.new, display_output: false, copy_from: nil)
            package_base_dir = File.expand_path(File.join('..', '..'), File.dirname(__FILE__))
            script = File.expand_path(name, scripts_dir)
            if !File.file?(script)
                raise ArgumentError, "no test script #{name} in #{scripts_dir}"
            end

            if seed_config
                arguments << '--seed-config' << seed_config
            end

            dir ||= make_tmpdir

            if gemfile_source || !use_autoproj_from_rubygems
                File.open(File.join(dir, 'Gemfile-dev'), 'w') do |io|
                    io.puts(gemfile_source || autoproj_gemfile_to_local_checkout)
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

        def fixture_gem_home
            File.join(__dir__, '..', '..', 'test', 'gem_home')
        end

        def prepare_fixture_gem_home
            FileUtils.rm_rf fixture_gem_home
            bundled_gems_path = File.expand_path(File.join("..", ".."), find_gem_dir('utilrb').full_gem_path)
            FileUtils.cp_r bundled_gems_path, fixture_gem_home

            vendor = File.join(__dir__, '..', '..', 'vendor')
            cached_bundler_gem = File.join(vendor, "bundler-#{Bundler::VERSION}.gem")
            if !File.file?(cached_bundler_gem)
                FileUtils.mkdir_p vendor
                if !system(Ops::Install.guess_gem_program, 'fetch', '-v', Bundler::VERSION, 'bundler', chdir: vendor)
                    raise "cannot download the bundler gem"
                end
            end

            capture_subprocess_io do
                system(Hash['GEM_HOME' => fixture_gem_home], Ops::Install.guess_gem_program, 'install', '--no-document', cached_bundler_gem)
            end
        end

        def start_gem_server(path = fixture_gem_home)
            require 'socket'
            require 'rubygems/server'
            if @gem_server_pid
                raise ArgumentError, "#start_gem_server already called, call stop_gem_server before calling start_gem_server again"
            end
            @gem_server_pid = spawn(Gem.ruby, Ops::Install.guess_gem_program, 'server', '--quiet', '--dir', path, out: :close, err: :close)
            while true
                begin TCPSocket.new('127.0.0.1', 8808)
                    break
                rescue Errno::ECONNREFUSED
                end
            end
        end

        def stop_gem_server
            Process.kill 'INT', @gem_server_pid
            Process.waitpid @gem_server_pid
            @gem_server_pid = nil
        end

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

    end
end

class Minitest::Test
    include Autoproj::SelfTest
end

