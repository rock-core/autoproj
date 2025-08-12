# simplecov must be loaded FIRST. Only the files required after it gets loaded
# will be profiled !!!
if ENV["TEST_ENABLE_COVERAGE"] == "1"
    begin
        require "simplecov"
        SimpleCov.start do
            command_name "master"
            add_filter "/test/"
        end
    rescue LoadError
        require "autoproj"
        Autoproj.warn "coverage is disabled because the 'simplecov' gem cannot be loaded"
    rescue Exception => e
        require "autoproj"
        Autoproj.warn "coverage is disabled: #{e.message}"
    end
end

require "minitest/autorun"
require "autoproj"
require "flexmock/minitest"
FlexMock.partials_are_based = true
require "minitest/spec"

if ENV["TEST_ENABLE_PRY"] != "0"
    begin
        require "pry"
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
            if ENV["AUTOPROJ_CURRENT_ROOT"]
                raise "cannot have a workspace's env.sh loaded while running the "\
                      "Autoproj test suite"
            end

            Autobuild.progress_display_mode = :newline

            if defined?(Autoproj::CLI::Main)
                Autoproj::CLI::Main.default_report_on_package_failures = :raise
            end
            FileUtils.rm_rf fixture_gem_home
            @gem_server_pid = nil
            @tmpdir = Array.new
            @ws = nil
            @ws_package_managers = Hash.new
            Autobuild.logdir = make_tmpdir
            ws_define_package_manager "os"
            ws_define_package_manager "os_indep"
            Autobuild.progress_display_period = 0

            super
        end

        def teardown
            super
            @tmpdir.each do |dir|
                FileUtils.remove_entry_secure dir
            end
            Rake::Task.clear
            Autobuild::Package.clear
            Autoproj.silent = false

            stop_gem_server if @gem_server_pid

            FileUtils.rm_rf fixture_gem_home
            if defined?(Autoproj::CLI::Main)
                Autoproj::CLI::Main.default_report_on_package_failures = nil
            end
            if ENV.delete("AUTOPROJ_CURRENT_ROOT")
                raise "AUTOPROJ_CURRENT_ROOT has been set by this test !!!!"
            end
        end

        def data_path(*args)
            File.expand_path(File.join(*args),
                             File.join(__dir__, "..", "..", "test", "data"))
        end

        def create_bootstrap
            ws_create
        end

        def skip_long_tests?
            ENV["AUTOPROJ_SKIP_LONG_TESTS"] == "1"
        end

        def make_tmpdir
            dir = Dir.mktmpdir
            @tmpdir << dir
            dir
        end

        def scripts_dir
            File.expand_path(File.join("..", "..", "test", "scripts"), __dir__)
        end

        def find_gem_dir(gem_name)
            Bundler.definition.specs.each do |spec|
                return spec if spec.name == gem_name
            end
            nil
        end

        def autoproj_gemfile_to_local_checkout
            autoproj_dir  = find_gem_dir("autoproj").full_gem_path
            autobuild_dir = find_gem_dir("autobuild").full_gem_path
            <<~GEMFILE
                source "https://rubygems.org"
                gem "autoproj", path: "#{autoproj_dir}"
                gem "autobuild", path: "#{autobuild_dir}"
            GEMFILE
        end

        def invoke_test_script(name, *arguments,
            dir: make_tmpdir,
            gemfile_source: nil,
            use_autoproj_from_rubygems: (ENV["USE_AUTOPROJ_FROM_RUBYGEMS"] == "1"),
            interactive: true,
            seed_config: File.join(scripts_dir, "seed-config.yml"),
            env: {}, display_output: false, copy_from: nil,
            **system_options)
            package_base_dir = File.expand_path(File.join("..", ".."), __dir__)

            script = File.expand_path(name, scripts_dir)
            unless File.file?(script)
                raise ArgumentError, "no test script #{name} in #{scripts_dir}"
            end

            if env["HOME"]
                @home_dir = env["HOME"]
            else
                env["HOME"] = (@home_dir ||= make_tmpdir)
            end
            arguments << "--seed-config" << seed_config if seed_config

            if gemfile_source || !use_autoproj_from_rubygems
                gemfile_path = File.join(dir, "Gemfile-dev")
                File.open(gemfile_path, "w") do |io|
                    io.puts(gemfile_source || autoproj_gemfile_to_local_checkout)
                end
                arguments << "--gemfile" << gemfile_path
            end

            arguments << "--no-interactive" unless interactive

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
                    "TEST_COMMAND_NAME" => to_s.gsub(/[^\w]/, "_"),
                    "PACKAGE_BASE_DIR" => package_base_dir,
                    "RUBY" => Gem.ruby
                ]
                result = Autoproj.bundler_unbundled_system(
                    default_env.merge(env), script, *arguments,
                    in: :close, **Hash[chdir: dir].merge(system_options)
                )
            end

            if !result
                puts stdout
                puts stderr
                flunk("test script #{name} failed")
            elsif display_output
                puts stdout
                puts stderr
            end
            [dir, stdout, stderr]
        end

        def fixture_gem_home
            File.join(__dir__, "..", "..", "vendor", "test_gem_home")
        end

        def prepare_fixture_gem_home
            FileUtils.rm_rf fixture_gem_home
            FileUtils.mkdir_p File.dirname(fixture_gem_home)
            bundled_gems_path = File.expand_path(File.join("..", ".."),
                                                 find_gem_dir("utilrb").full_gem_path)
            FileUtils.cp_r bundled_gems_path, fixture_gem_home

            vendor = File.join(__dir__, "..", "..", "vendor")
            bundler_filename = "bundler-#{Bundler::VERSION}.gem"
            cached_bundler_gem = File.join(vendor, bundler_filename)
            unless File.file?(cached_bundler_gem)
                FileUtils.mkdir_p vendor
                Autoproj.bundler_unbundled_system(
                    Ops::Install.guess_gem_program, "fetch", "-v",
                    Bundler::VERSION, "bundler", chdir: vendor
                )

                unless File.file?(cached_bundler_gem)
                    existing = Dir.enum_for(:glob, File.join(vendor, "*")).to_a.sort
                    raise "cannot download the bundler gem. "\
                          "Expected #{bundler_filename}, found: #{existing.join(', ')}"
                end
            end

            capture_subprocess_io do
                Autoproj.bundler_unbundled_system(
                    Hash["GEM_HOME" => fixture_gem_home, "GEM_PATH" => nil],
                    Ops::Install.guess_gem_program, "install", "--no-document",
                    cached_bundler_gem
                )
            end
        end

        def start_gem_server(path = fixture_gem_home)
            require "socket"
            require "rubygems/server"
            if @gem_server_pid
                raise ArgumentError,
                      "#start_gem_server already called, "\
                      "call stop_gem_server before calling start_gem_server again"
            end
            @gem_server_pid = spawn(
                Hash[
                    "RUBYOPT" => nil,
                    "GEM_HOME" => path,
                    "BUNDLE_GEMFILE" => nil,
                    "BUNDLER_SETUP" => nil
                ],
                Gem.ruby, Ops::Install.guess_gem_program, "server",
                "--quiet", "--dir", path, out: :close, err: :close
            )
            loop do
                TCPSocket.new("127.0.0.1", 8808)
                break
            rescue Errno::ECONNREFUSED
            end
        end

        def stop_gem_server
            Process.kill "INT", @gem_server_pid
            Process.waitpid @gem_server_pid
            @gem_server_pid = nil
        end

        def capture_deprecation_message
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
            result = Autoproj.bundler_unbundled_system(
                bundler, "show", gem_name,
                out: out_w,
                chdir: File.dirname(gemfile)
            )
            out_w.close
            output = out_r.read.chomp
            assert result, "bundler show #{gem_name} failed, output: '#{output}'"
            output
        end

        def workspace_env(dir, varname)
            _, stdout, = invoke_test_script "display-env.sh", varname, dir: dir
            stdout.chomp
        end

        def in_ws
            Dir.chdir(@ws.root_dir) do
                yield
            end
        end

        attr_reader :ws_os_package_resolver

        def ws_define_package_manager(name, strict: false, call_while_empty: false)
            manager = Class.new(PackageManagers::Manager)
            manager.class_eval do
                define_method(:strict?) { strict }
                define_method(:call_while_empty?) { call_while_empty }
            end
            manager = flexmock(manager)
            ws_package_managers[name] = manager
        end

        def ws_create_os_package_resolver
            @ws_os_package_resolver = OSPackageResolver.new(
                operating_system: [["test_os_family"], ["test_os_version"]],
                package_managers: ws_package_managers.keys,
                os_package_manager: "os"
            )
        end

        def ws_create(dir = make_tmpdir, partial_config: false)
            require "autoproj/ops/main_config_switcher"
            FileUtils.cp_r Ops::MainConfigSwitcher::MAIN_CONFIGURATION_TEMPLATE,
                           File.join(dir, "autoproj")
            FileUtils.mkdir_p File.join(dir, ".autoproj")

            ws_create_os_package_resolver
            @ws = Workspace.new(
                dir, os_package_resolver: ws_os_package_resolver,
                     package_managers: ws_package_managers
            )

            unless partial_config
                ws.config.set "osdeps_mode", "all"
                ws.config.set "apt_dpkg_update", true
            end
            ws.config.set "GITHUB", "http,ssh", true
            ws.config.set "GITORIOUS", "http,ssh", true
            ws.config.set "gems_install_path", File.join(dir, "gems")
            ws.prefix_dir = make_tmpdir
            ws.config.save

            # Make a valid (albeit empty) Gemfile
            File.open(File.join(ws.dot_autoproj_dir, "Gemfile"), "w").close
            # Create the shims folder
            FileUtils.mkdir File.join(ws.dot_autoproj_dir, "bin")
            ws
        end

        def ws_clear_layout
            ws.manifest.clear_layout
        end

        def ws_define_package_set(
            name, vcs = VCSDefinition.from_raw({ type: "none" }),
            raw_local_dir: PackageSet.raw_local_dir_of(ws, vcs)
        )
            package_set = PackageSet.new(
                ws, vcs, name: name, raw_local_dir: raw_local_dir
            )
            ws.manifest.register_package_set(package_set)
            package_set
        end

        def ws_create_local_package_set(name, path, source_data: Hash.new, **options)
            vcs = VCSDefinition.from_raw({ type: "local", url: path })
            package_set = PackageSet.new(ws, vcs, name: name, **options)
            FileUtils.mkdir_p(path)
            File.open(File.join(path, "source.yml"), "w") do |io|
                YAML.dump(Hash["name" => name].merge(source_data), io)
            end
            ws.manifest.register_package_set(package_set)
            package_set
        end

        def ws_add_package_set_to_layout(
            name, vcs = VCSDefinition.from_raw({ type: "none" }), **options
        )
            package_set = ws_define_package_set(name, vcs, **options)
            ws.manifest.add_package_set_to_layout(package_set)
            package_set
        end

        def ws_add_metapackage_to_layout(name, *packages)
            meta = ws.manifest.metapackage(name, *packages)
            ws.manifest.add_metapackage_to_layout(meta)
            meta
        end

        def ws_define_osdep_entries(entries, file: nil)
            ws_os_package_resolver.add_entries(entries, file: file)
        end

        def ws_add_osdep_entries_to_layout(entries)
            ws_os_package_resolver.add_entries(entries)
            entries.each_key do |pkg_name|
                ws.manifest.add_package_to_layout(pkg_name)
            end
        end

        def ws_define_package(package_type, package_name,
            package_set: ws.manifest.main_package_set,
            create: true, &block)
            package = Autobuild.send(package_type, package_name)
            ws_setup_package(
                package, package_set: package_set, create: create, &block
            )
        end

        def ws_setup_package(package, package_set: ws.manifest.main_package_set,
            create: true)
            package.srcdir = File.join(ws.root_dir, package.name.to_s)
            FileUtils.mkdir_p package.srcdir if create
            autoproj_package = ws.register_package(package, nil, package_set)
            yield(package) if block_given?
            autoproj_package
        end

        def ws_define_package_vcs(package, vcs_spec)
            package.package_set.add_version_control_entry(package.name, vcs_spec)
        end

        def ws_resolve_vcs(package)
            package.vcs = ws.manifest.importer_definition_for(package)
        end

        def ws_define_package_overrides(package, package_set, vcs_spec)
            package_set.add_overrides_entry(package.name, vcs_spec)
        end

        def ws_add_package_to_layout(package_type, package_name,
            package_set: ws.manifest.main_package_set, &block)
            pkg = ws_define_package(package_type, package_name,
                                    package_set: package_set, &block)
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
            package.autobuild.builddir = builddir =
                File.join(ws.root_dir, "build", package.name)
            package.autobuild.prefix = prefix =
                File.join(ws.root_dir, "prefix", package.name)
            [srcdir, builddir, prefix]
        end

        def ws_create_git_package_set(name, source_data = Hash.new)
            dir = make_tmpdir
            unless system("git", "init", chdir: dir, out: :close)
                raise "failed to run git init"
            end

            File.open(File.join(dir, "source.yml"), "w") do |io|
                YAML.dump(Hash["name" => name].merge(source_data), io)
            end
            unless system("git", "add", "source.yml", chdir: dir, out: :close)
                raise "failed to add the source.yml"
            end

            unless system("git", "commit", "-m", "add source.yml",
                          chdir: dir, out: :close)
                raise "failed to commit the source.yml"
            end

            dir
        end

        def ws_create_package_set_file(pkg_set, name, content)
            path = File.join(pkg_set.raw_local_dir, name)
            FileUtils.mkdir_p File.dirname(path)
            File.open(path, "w") do |io|
                io.write content
            end
            path
        end

        def ws_create_package_file(pkg, name, content)
            path = File.join(pkg.autobuild.srcdir, name)
            FileUtils.mkdir_p File.dirname(path)
            File.open(path, "w") do |io|
                io.write content
            end
            path
        end

        def gemfile_aruba
            base_dir = File.expand_path("../../", __dir__)
            gemfile_path = File.join(base_dir, "tmp", "Gemfile.local")
            File.open(gemfile_path, "w") do |io|
                io.write <<~GEMFILE
                source 'https://rubygems.org'
                gem 'autoproj', path: '#{base_dir}'
                GEMFILE
            end
            gemfile_path
        end
    end
end

class Minitest::Test # rubocop:disable Style/ClassAndModuleChildren
    include Autoproj::SelfTest
end
