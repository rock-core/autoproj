# simplecov must be loaded FIRST. Only the files required after it gets loaded
# will be profiled !!!
if ENV['TEST_ENABLE_COVERAGE'] == '1'
    begin
        require 'simplecov'
        SimpleCov.start do
            command_name 'master'
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
FlexMock.partials_are_based = true
FlexMock.partials_verify_signatures = true
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
        # Define package managers for the next workspace created by {#ws_create}
        #
        # Use {#ws_define_package_manager}
        #
        # Two package managers called 'os' and 'os_indep' are always created,
        # 'os' is used as the os package manager.
        #
        # @return [Hash<String,PackageManagers::Manager>]
        attr_reader :ws_package_managers
        # The workspace created by the last call to #ws_create
        attr_reader :ws

        def setup
            FileUtils.rm_rf fixture_gem_home
            @gem_server_pid = nil
            @tmpdir = Array.new
            @ws = nil
            @ws_package_managers = Hash.new
            Autobuild.logdir = make_tmpdir
            ws_define_package_manager 'os'
            ws_define_package_manager 'os_indep'

            super
        end

        def teardown
            super
            @tmpdir.each do |dir|
                FileUtils.remove_entry_secure dir
            end
            Autobuild::Package.clear
            Autoproj.silent = false

            if @gem_server_pid
                stop_gem_server
            end

            FileUtils.rm_rf fixture_gem_home
        end

        def create_bootstrap
            ws_create
        end

        def skip_long_tests?
            ENV['AUTOPROJ_SKIP_LONG_TESTS'] == '1'
        end

        def make_tmpdir
            dir = Dir.mktmpdir
            @tmpdir << dir
            dir
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
                               env: Hash.new, display_output: false, copy_from: nil,
                               **system_options)
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
                gemfile_path = File.join(dir, 'Gemfile-dev')
                File.open(gemfile_path, 'w') do |io|
                    io.puts(gemfile_source || autoproj_gemfile_to_local_checkout)
                end
                arguments << "--gemfile" << gemfile_path << "--gem-source" << "http://localhost:8808"
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
                default_env = Hash[
                    'TEST_COMMAND_NAME' => self.to_s.gsub(/[^\w]/, '_'),
                    'PACKAGE_BASE_DIR' => package_base_dir,
                    'RUBY' => Gem.ruby
                ]
                result = Bundler.clean_system(
                    default_env.merge(env),
                    script, *arguments, in: :close, **Hash[chdir: dir].merge(system_options))
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
            File.join(__dir__, '..', '..', 'vendor', 'test_gem_home')
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
                Bundler.clean_system(Hash['GEM_HOME' => fixture_gem_home, 'GEM_PATH' => nil], Ops::Install.guess_gem_program, 'install', '--no-document', cached_bundler_gem)
            end
        end

        def start_gem_server(path = fixture_gem_home)
            require 'socket'
            require 'rubygems/server'
            if @gem_server_pid
                raise ArgumentError, "#start_gem_server already called, call stop_gem_server before calling start_gem_server again"
            end
            @gem_server_pid = spawn(Hash['RUBYOPT' => nil], Gem.ruby, Ops::Install.guess_gem_program, 'server', '--quiet', '--dir', path, out: :close, err: :close)
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

        def capture_deprecation_message(&block)
            level = Autoproj.warn_deprecated_level
            Autoproj.warn_deprecated_level = -1
            capture_subprocess_io do
                yield
            end
        ensure
            Autoproj.warn_deprecated_level = level
        end

        def find_bundled_gem_path(bundler, gem_name, gemfile)
            out_r, out_w = IO.pipe
            result = Bundler.clean_system(
                bundler, 'show', gem_name,
                out: out_w,
                chdir: File.dirname(gemfile))
            out_w.close
            output = out_r.read.chomp
            assert result, "#{output}"
            output
        end

        def workspace_env(varname)
            _, stdout, _ = invoke_test_script 'display-env.sh', varname, dir: install_dir
            stdout.chomp
        end

        attr_reader :ws_os_package_resolver

        def ws_define_package_manager(name, strict: false, call_while_empty: false)
            manager = Class.new(PackageManagers::Manager)
            manager.class_eval do
                define_method(:strict?) { strict }
                define_method(:call_while_empty?) { call_while_empty }
            end
            manager = flexmock(manager),
            ws_package_managers[name] = manager
        end

        def ws_create_os_package_resolver
            @ws_os_package_resolver = OSPackageResolver.new(
                operating_system: [['test_os_family'], ['test_os_version']],
                package_managers: ws_package_managers.keys,
                os_package_manager: 'os')
        end

        def ws_create
            dir = make_tmpdir
            require 'autoproj/ops/main_config_switcher'
            FileUtils.cp_r Ops::MainConfigSwitcher::MAIN_CONFIGURATION_TEMPLATE, File.join(dir, 'autoproj')
            FileUtils.mkdir_p File.join(dir, '.autoproj')

            ws_create_os_package_resolver
            @ws = Workspace.new(
                dir, os_package_resolver: ws_os_package_resolver,
                     package_managers: ws_package_managers)
            ws.config.set 'osdeps_mode', 'all'
            ws.config.set 'gems_install_path', File.join(dir, 'gems')
            ws.config.save
            ws.prefix_dir = make_tmpdir
            ws
        end

        def ws_clear_layout
            ws.manifest.clear_layout
        end

        def ws_define_package_set(name, vcs = VCSDefinition.from_raw(type: 'none'), **options)
            package_set = PackageSet.new(ws, vcs, name: name, **options)
            ws.manifest.register_package_set(package_set)
            package_set
        end

        def ws_create_local_package_set(name, path, source_data: Hash.new, **options)
            vcs = VCSDefinition.from_raw(type: 'local', url: path)
            package_set = PackageSet.new(ws, vcs, name: name, **options)
            FileUtils.mkdir_p(path)
            File.open(File.join(path, 'source.yml'), 'w') do |io|
                YAML.dump(Hash['name' => name].merge(source_data), io)
            end
            ws.manifest.register_package_set(package_set)
            package_set
        end

        def ws_add_package_set_to_layout(name, vcs = VCSDefinition.from_raw(type: 'none'), **options)
            package_set = ws_define_package_set(name, vcs, **options)
            ws.manifest.add_package_set_to_layout(package_set)
            package_set
        end

        def ws_add_metapackage_to_layout(name, *packages)
            meta = ws.manifest.metapackage(name, *packages)
            ws.manifest.add_metapackage_to_layout(meta)
            meta
        end

        def ws_define_osdep_entries(entries)
            ws_os_package_resolver.add_entries(entries)
        end

        def ws_add_osdep_entries_to_layout(entries)
            ws_os_package_resolver.add_entries(entries)
            entries.each_key do |pkg_name|
                ws.manifest.add_package_to_layout(pkg_name)
            end
        end

        def ws_define_package(package_type, package_name, package_set: ws.manifest.main_package_set, create: true)
            package = Autobuild.send(package_type, package_name)
            package.srcdir = File.join(ws.root_dir, package_name.to_s)
            if create
                FileUtils.mkdir_p package.srcdir
            end
            autoproj_package = ws.register_package(package, nil, package_set)
            yield(package) if block_given?
            autoproj_package
        end

        def ws_define_package_vcs(package, vcs_spec)
            package.package_set.add_version_control_entry(package.name, vcs_spec)
        end

        def ws_define_package_overrides(package, package_set, vcs_spec)
            package_set.add_overrides_entry(package.name, vcs_spec)
        end

        def ws_add_package_to_layout(package_type, package_name, package_set: ws.manifest.main_package_set, &block)
            pkg = ws_define_package(package_type, package_name, package_set: package_set, &block)
            ws.manifest.add_package_to_layout(pkg)
            pkg
        end

        def ws_set_version_control_entry(package, entry)
            package.package_set.add_version_control_entry(package.name, entry)
        end

        def ws_set_overrides_entry(package, package_set, entry)
            package_set.add_overrides_entry(package.name, entry)
        end

        def ws_setup_package_dirs(package, create_srcdir: true)
            package.autobuild.srcdir = srcdir = File.join(ws.root_dir, package.name)
            if create_srcdir
                FileUtils.mkdir_p srcdir
            elsif File.directory?(srcdir)
                FileUtils.rm_rf srcdir
            end
            package.autobuild.builddir = builddir = File.join(ws.root_dir, 'build', package.name)
            package.autobuild.prefix = prefix = File.join(ws.root_dir, 'prefix', package.name)
            return srcdir, builddir, prefix
        end

        def ws_create_git_package_set(name, source_data = Hash.new)
            dir = make_tmpdir
            if !system('git', 'init', chdir: dir, out: :close)
                raise "failed to run git init"
            end
            File.open(File.join(dir, 'source.yml'), 'w') do |io|
                YAML.dump(Hash['name' => name].merge(source_data), io)
            end
            if !system('git', 'add', 'source.yml', chdir: dir, out: :close)
                raise "failed to add the source.yml"
            end
            if !system('git', 'commit', '-m', 'add source.yml', chdir: dir, out: :close)
                raise "failed to commit the source.yml"
            end
            dir
        end
    end
end

class Minitest::Test
    include Autoproj::SelfTest
end

