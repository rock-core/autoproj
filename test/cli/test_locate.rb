require 'autoproj/test'
require 'autoproj/cli/locate'

module Autoproj
    module CLI
        describe Locate do
            attr_reader :cli, :installation_manifest
            before do
                ws_create
                @installation_manifest = InstallationManifest.new(
                    ws.installation_manifest_path)
                @cli = Locate.new(ws, installation_manifest: installation_manifest)
                flexmock(cli)
            end

            describe "#validate_options" do
                it "transforms the prefix: true CLI option into a run mode" do
                    assert_equal [['test'], Hash[test: 10, mode: :prefix_dir]],
                        cli.validate_options(['test'], Hash[test: 10, prefix: true])
                end
                it "transforms the build: true CLI option into a run mode" do
                    assert_equal [['test'], Hash[test: 10, mode: :build_dir]],
                        cli.validate_options(['test'], Hash[test: 10, build: true])
                end
                it "removes prefix: false from the options" do
                    assert_equal [['test'], Hash[test: 10, mode: :source_dir]],
                        cli.validate_options(['test'], Hash[test: 10, prefix: false])
                end
                it "removes build: false from the options" do
                    assert_equal [['test'], Hash[test: 10, mode: :source_dir]],
                        cli.validate_options(['test'], Hash[test: 10, build: false])
                end
                it "removes both prefix: false and build: false from the options" do
                    assert_equal [['test'], Hash[test: 10, mode: :source_dir]],
                        cli.validate_options(['test'], Hash[test: 10, prefix: false, build: false])
                end
                it "returns the only argument" do
                    assert_equal [['test'], Hash[test: 10, mode: :source_dir]],
                        cli.validate_options(['test'], Hash[test: 10])
                end
                it "'selects' the workspace root dir if no arguments are given" do
                    assert_equal [[ws.root_dir], Hash[test: 10, mode: :source_dir]],
                        cli.validate_options([], Hash[test: 10])
                end
            end

            describe "#try_loading_installation_manifest" do
                it "returns nil if no manifest exists" do
                    assert_nil cli.try_loading_installation_manifest(ws)
                end
                it "returns the manifest object if a manifest exists" do
                    ws.export_installation_manifest
                    manifest = cli.try_loading_installation_manifest(ws)
                    assert_kind_of InstallationManifest, manifest
                end
            end

            describe "#initialize_from_workspace" do
                attr_reader :cli

                before do
                    ws_create
                    @cli = Locate.new(ws, installation_manifest: nil)
                    flexmock(cli)
                    cli.should_receive(:initialize_and_load)
                end

                it "updates the installation manifest and then uses it" do
                    src    = File.join(ws.root_dir, 'src')
                    build  = File.join(ws.root_dir, 'build')
                    prefix = File.join(ws.root_dir, 'prefix')
                    package = ws_add_package_to_layout :cmake, 'package'
                    package.autobuild.srcdir = src
                    package.autobuild.builddir = build
                    package.autobuild.prefix = prefix
                    cli.initialize_from_workspace

                    assert_equal src, cli.source_dir_of('package')
                    assert_equal src, cli.source_dir_of("#{src}/")
                    assert_equal src, cli.source_dir_of("#{build}/")
                    assert_equal build, cli.build_dir_of('package')
                    assert_equal prefix, cli.prefix_dir_of('package')
                end
            end

            describe "#find_package_set" do
                attr_reader :user_dir, :raw_dir, :pkg_set
                before do
                    @user_dir = make_tmpdir
                    @raw_dir  = make_tmpdir
                    @pkg_set = InstallationManifest::PackageSet.new(
                        'rock.core', Hash.new, raw_dir, user_dir)
                    installation_manifest.add_package_set(pkg_set)
                    cli.update_from_installation_manifest(installation_manifest)
                end
                it "returns nil if nothing matches" do
                    assert_nil cli.find_package_set('does.not.exist')
                end
                it "matches a package set by name" do
                    assert_same pkg_set, cli.find_package_set('rock.core')
                end
                it "matches a package set by raw local dir" do
                    assert_same pkg_set, cli.find_package_set("#{raw_dir}/")
                end
                it "matches a package set by user local dir" do
                    assert_same pkg_set, cli.find_package_set("#{user_dir}/")
                end
                it "matches a subdirectory of the raw local dir" do
                    assert_same pkg_set, cli.find_package_set("#{raw_dir}/manifests/")
                end
                it "matches a subdirectory of the user local dir" do
                    assert_same pkg_set, cli.find_package_set("#{user_dir}/test/")
                end
            end

            describe "#find_packages" do
                attr_reader :pkg
                before do
                    @pkg = InstallationManifest::Package.new(
                        'pkg', 'Autobuild::CMake', Hash.new, '/srcdir', '/srcdir',
                                                             '/prefix', '/builddir', [])
                    installation_manifest.add_package(pkg)
                    cli.update_from_installation_manifest(installation_manifest)
                end

                it "returns an empty array if there are no matches" do
                    assert_equal [], cli.find_packages('does/not/exist')
                end
                it "matches against the name" do
                    assert_equal [pkg], cli.find_packages('pkg')
                end
                it "matches against the source directory" do
                    assert_equal [pkg], cli.find_packages('/srcdir/')
                end
                it "matches against a subdirectory of the source directory" do
                    assert_equal [pkg], cli.find_packages('/srcdir/sub')
                end
                it "matches against the build directory" do
                    assert_equal [pkg], cli.find_packages('/builddir/')
                end
                it "matches against a subdirectory of the build directory" do
                    assert_equal [pkg], cli.find_packages('/builddir/sub')
                end
                it "handles packages without build directories" do
                    pkg.builddir = nil
                    assert_equal [pkg], cli.find_packages('/srcdir/sub')
                end
                it "returns regexp-based matches on the name if there are no exact matches" do
                    expected = %w{test0 test1}.map do |pkg_name|
                        pkg = InstallationManifest::Package.new(
                            pkg_name, 'Autobuild::CMake', Hash.new, '/srcdir', '/srcdir',
                                                                    '/prefix', '/builddir', [])
                        installation_manifest.add_package(pkg)
                    end
                    cli.update_from_installation_manifest(installation_manifest)
                    assert_equal expected, cli.find_packages('test')
                end
                it "ignores regexp-based matches if there are exact matches" do
                    test0 = InstallationManifest::Package.new(
                        'pkg0', 'Autobuild::CMake', Hash.new, '/srcdir', '/srcdir',
                                                              '/prefix', '/builddir', []
                    )
                    installation_manifest.add_package(test0)
                    test1 = InstallationManifest::Package.new(
                        'pkg1', 'Autobuild::CMake', Hash.new, '/srcdir', '/srcdir',
                                                              '/prefix', '/builddir', []
                    )
                    installation_manifest.add_package(test1)
                    assert_equal [pkg], cli.find_packages('pkg')
                    assert_equal [pkg], cli.find_packages('/srcdir/')
                    assert_equal [pkg], cli.find_packages('/srcdir/sub/')
                    assert_equal [pkg], cli.find_packages('/builddir/')
                    assert_equal [pkg], cli.find_packages('/builddir/sub/')
                end
            end

            describe "#find_packages_with_directory_shortnames" do
                def add_packages(*names)
                    packages = names.map do |n|
                        pkg = InstallationManifest::Package.new(n)
                        installation_manifest.add_package(pkg)
                        pkg
                    end
                    cli.update_from_installation_manifest(installation_manifest)
                    packages
                end

                it "returns an empty array if there are no matches" do
                    add_packages 'path/to/pkg'
                    assert_equal [], cli.find_packages_with_directory_shortnames('does/not/exist')
                end
                it "matches based on partial directory prefixes" do
                    # Add other matches
                    matches = add_packages \
                        'path/to/pkg', 'possibly/to/pkg', 'path/trivially/pkg', 'path/to/potential_match'
                    # Add things that should not match
                    add_packages 'other/to/pkg', 'path/other/pkg', 'path/to/other'
                    assert_equal matches, cli.find_packages_with_directory_shortnames('p/t/p')
                end
                it "will favor a package that exactly matches the last part of the selection over the other" do
                    pkg = add_packages('path/to/pkg').first
                    add_packages 'path/to/pkg_test', 'path/to/pkg_other'
                    assert_equal [pkg], cli.find_packages_with_directory_shortnames('p/t/pkg')
                end
            end

            describe "#run" do
                it "raises if given an invalid mode" do
                    e = assert_raises(ArgumentError) do
                        cli.run([ws.root_dir], mode: :invalid)
                    end
                    assert_match(/'#{:invalid}' was expected to be one of/, e.message)
                end

                it "does not load the configuration if initialized with an installation manifest" do
                    cli.should_receive(:initialize_from_workspace).never
                    capture_subprocess_io do
                        cli.run([ws.root_dir])
                    end
                end
                it "loads the configuration and updates the manifest if cache: false" do
                    cli.should_receive(:initialize_from_workspace).once
                    capture_subprocess_io do
                        cli.run([ws.root_dir], cache: false)
                    end
                end

                it "expands a relative path to an absolute and appends a slash before matching" do
                    absolute_dir = make_tmpdir
                    dir = Pathname.new(absolute_dir).relative_path_from(Pathname.pwd).to_s
                    cli.should_receive(:source_dir_of).with("#{absolute_dir}/").
                        once
                    capture_subprocess_io do
                        cli.run([dir])
                    end
                end
                it "displays the result of source_dir_of if mode: :source_dir" do
                    cli.should_receive(:source_dir_of).with('selection').
                        and_return('test')
                    out, _ = capture_subprocess_io do
                        cli.run(['selection'], mode: :source_dir)
                    end
                    assert_equal 'test', out.chomp
                end
                it "displays the result of build_dir_of if mode: :build_dir" do
                    cli.should_receive(:build_dir_of).with('selection').
                        and_return('test')
                    out, _ = capture_subprocess_io do
                        cli.run(['selection'], mode: :build_dir)
                    end
                    assert_equal 'test', out.chomp
                end
                it "displays the result of prefix_dir_of if mode: :prefix_dir" do
                    cli.should_receive(:prefix_dir_of).with('selection').
                        and_return('test')
                    out, _ = capture_subprocess_io do
                        cli.run(['selection'], mode: :prefix_dir)
                    end
                    assert_equal 'test', out.chomp
                end
                it "displays the result of log_of if mode: :log" do
                    cli.should_receive(:logs_of).with('selection', log: nil).
                        and_return(['test'])
                    out, _ = capture_subprocess_io do
                        cli.run(['selection'], mode: :log)
                    end
                    assert_equal 'test', out.chomp
                end
                it "selects one log file if logs_of returns more than one" do
                    cli.should_receive(:logs_of).with('selection', log: nil).
                        and_return(candidates = [flexmock, flexmock])
                    cli.should_receive(:select_log_file).with(candidates).
                        and_return('test')
                    out, _ = capture_subprocess_io do
                        cli.run(['selection'], mode: :log)
                    end
                    assert_equal 'test', out.chomp
                end
                it "interprets log: 'all' as 'show all the log files'" do
                    cli.should_receive(:logs_of).with('selection', log: nil).
                        and_return(['two', 'files'])
                    out, _ = capture_subprocess_io do
                        cli.run(['selection'], mode: :log, log: 'all')
                    end
                    assert_equal "two\nfiles\n", out
                end
                it "passes the 'log' option to log_of" do
                    cli.should_receive(:logs_of).with('selection', log: 'install').
                        and_return(['test'])
                    out, _ = capture_subprocess_io do
                        cli.run(['selection'], mode: :log, log: 'install')
                    end
                    assert_equal 'test', out.chomp
                end
                it "raises if there are no log files and log is not 'all'" do
                    cli.should_receive(:logs_of).and_return([])
                    e = assert_raises(Locate::NotFound) do
                        cli.run(['selection'], mode: :log)
                    end
                    assert_equal 'no logs found for selection', e.message
                end
            end

            describe "#source_dir_of" do
                it "returns the workspace's root" do
                    FileUtils.mkdir_p ws.prefix_dir
                    assert_equal ws.root_dir, cli.source_dir_of("#{ws.root_dir}/")
                    assert_equal ws.root_dir, cli.source_dir_of("#{ws.prefix_dir}/")
                end
                it "returns a package set's user_local_dir" do
                    cli.should_receive(:find_package_set).
                        with(selection = flexmock).
                        and_return(flexmock(user_local_dir: 'usr/local/dir'))
                    assert_equal 'usr/local/dir', cli.source_dir_of(selection)
                end
                it "returns a package's source directory" do
                    dir = flexmock
                    cli.should_receive(:resolve_package).
                        with(selection = flexmock).
                        and_return(flexmock(srcdir: dir))
                    assert_equal dir, cli.source_dir_of(selection)
                end
            end

            describe "#logs_of" do
                attr_reader :pkg, :logdir
                before do
                    @pkg = ws_define_package :cmake, 'test/pkg'
                    pkg.autobuild.logdir = (@logdir = make_tmpdir)
                    FileUtils.mkdir_p File.join(logdir, 'test')
                    FileUtils.touch File.join(logdir, 'test', 'pkg-install.log')
                    FileUtils.touch File.join(logdir, 'test', 'pkg-build.log')
                    cli.should_receive(:initialize_and_load)
                    cli.initialize_from_workspace
                end

                describe "handling of the workspace" do
                    it "returns an empty array if the workspace's main configuration import log does not exist" do
                        assert_equal [], cli.logs_of("#{ws.root_dir}/")
                    end

                    it "returns the workspace's main configuration import log does not exist" do
                        flexmock(ws, log_dir: make_tmpdir)
                        logfile = File.join(ws.log_dir, 'autoproj main configuration-import.log')
                        FileUtils.touch logfile
                        assert_equal [logfile], cli.logs_of("#{ws.root_dir}/")
                        assert_equal [logfile], cli.logs_of("#{ws.root_dir}/", log: 'import')
                    end

                    it "returns an empty array if 'log' is anything but nil or 'import'" do
                        flexmock(ws, log_dir: make_tmpdir)
                        logfile = File.join(ws.log_dir, 'autoproj main configuration-import.log')
                        FileUtils.touch logfile
                        assert_equal [], cli.logs_of("#{ws.root_dir}/", log: 'build')
                    end
                end

                describe "handling of package sets" do
                    it "returns an empty array if the package set's import log does not exist" do
                        cli.should_receive(:find_package_set).
                            and_return(flexmock(name: 'test'))
                        assert_equal [], cli.logs_of(flexmock)
                    end

                    it "returns the package set's import log if it exists" do
                        flexmock(ws, log_dir: make_tmpdir)
                        cli.should_receive(:find_package_set).
                            and_return(flexmock(name: 'test'))
                        logfile = File.join(ws.log_dir, 'test-import.log')
                        FileUtils.touch logfile
                        assert_equal [logfile], cli.logs_of(flexmock)
                    end

                    it "returns an empty array if 'log' is anything but nil or 'import'" do
                        flexmock(ws, log_dir: make_tmpdir)
                        cli.should_receive(:find_package_set).
                            and_return(flexmock(name: 'test'))
                        logfile = File.join(ws.log_dir, 'autoproj main configuration-import.log')
                        FileUtils.touch logfile
                        assert_equal [], cli.logs_of(flexmock, log: 'build')
                    end
                end

                describe "handling of packages" do
                    it "returns an empty array if the package has no logs" do
                        pkg.autobuild.logdir = make_tmpdir
                        assert_equal [], cli.logs_of('test/pkg')
                    end

                    it "lists a package's log files" do
                        expected = Set[
                            File.join(logdir, 'test', 'pkg-build.log'),
                            File.join(logdir, 'test', 'pkg-install.log')
                        ]
                        assert_equal expected, cli.logs_of('test/pkg').to_set
                    end
                end
            end

            describe "#prefix_dir_of" do
                it "returns the workspace's prefix" do
                    FileUtils.mkdir_p ws.prefix_dir
                    assert_equal ws.prefix_dir, cli.prefix_dir_of("#{ws.root_dir}/")
                    assert_equal ws.prefix_dir, cli.prefix_dir_of("#{ws.prefix_dir}/")
                end
                it "raises NoSuchDir if given a package set" do
                    cli.should_receive(:find_package_set).with(selection = flexmock).and_return(flexmock)
                    e = assert_raises(Locate::NoSuchDir) do
                        cli.prefix_dir_of(selection)
                    end
                    assert_equal "#{selection} is a package set, and package sets do not have prefixes",
                        e.message
                end
                it "returns a package's prefix directory" do
                    dir = flexmock
                    cli.should_receive(:resolve_package).
                        with(selection = flexmock).
                        and_return(flexmock(prefix: dir))
                    assert_equal dir, cli.prefix_dir_of(selection)
                end
            end

            describe "#build_dir_of" do
                it "raises NoSuchDir if selecting the workspace" do
                    FileUtils.mkdir_p ws.prefix_dir
                    e = assert_raises(Locate::NoSuchDir) do
                        cli.build_dir_of("#{ws.root_dir}/")
                    end
                    assert_equal "#{ws.root_dir}/ points to the workspace itself, which has no build dir",
                        e.message
                    e = assert_raises(Locate::NoSuchDir) do
                        cli.build_dir_of("#{ws.prefix_dir}/")
                    end
                    assert_equal "#{ws.prefix_dir}/ points to the workspace itself, which has no build dir",
                        e.message
                end
                it "raises NoSuchDir if given a package set" do
                    cli.should_receive(:find_package_set).with(selection = flexmock).and_return(flexmock)
                    e = assert_raises(Locate::NoSuchDir) do
                        cli.build_dir_of(selection)
                    end
                    assert_equal "#{selection} is a package set, and package sets do not have build directories",
                        e.message
                end
                it "returns a package's prefix directory" do
                    dir = flexmock
                    cli.should_receive(:resolve_package).
                        with(selection = flexmock).
                        and_return(flexmock(builddir: dir))
                    assert_equal dir, cli.build_dir_of(selection)
                end
                it "raises Locate::NoSuchDir if the matching package has no build directory" do
                    cli.should_receive(:resolve_package).
                        with(selection = flexmock).
                        and_return(flexmock(name: 'test'))
                    e = assert_raises(Locate::NoSuchDir) do
                        cli.build_dir_of(selection)
                    end
                    assert_equal "#{selection} resolves to the package test, which does not have a build directory", e.message
                end
                it "raises NoSuchDir if the package has a nil build directory" do
                    cli.should_receive(:resolve_package).
                        with(selection = flexmock).
                        and_return(flexmock(name: 'test', builddir: nil))
                    e = assert_raises(Locate::NoSuchDir) do
                        cli.build_dir_of(selection)
                    end
                    assert_equal "#{selection} resolves to the package test, which does not have a build directory", e.message
                end
            end

            describe "#select_log_file" do
                attr_reader :base_dir
                before do
                    @base_dir = make_tmpdir
                    FileUtils.touch File.join(base_dir, 'package-install.log')
                    FileUtils.touch File.join(base_dir, 'package-build.log')
                    FileUtils.touch File.join(base_dir, 'package.log')
                end

                def selection_choice(name, path)
                    return "(#{File.stat(path).mtime}) #{name}", path
                end

                it "attempts to select a log file and return it" do
                    choices = Hash[*selection_choice('install', "#{base_dir}/package-install.log"),
                                   *selection_choice('build', "#{base_dir}/package-build.log")]
                    flexmock(TTY::Prompt).new_instances.
                        should_receive(:select).with('Select the log file', choices).
                        and_return('result')
                    assert_equal 'result', cli.select_log_file(
                        ["#{base_dir}/package-install.log",
                         "#{base_dir}/package-build.log"])
                end

                it "prompts with the full path if it does not match the expected pattern" do
                    choices = Hash[*selection_choice("#{base_dir}/package.log", "#{base_dir}/package.log"),
                                   *selection_choice('build', "#{base_dir}/package-build.log")]
                    flexmock(TTY::Prompt).new_instances.
                        should_receive(:select).with('Select the log file', choices).
                        and_return('result')
                    assert_equal 'result', cli.select_log_file(
                        ["#{base_dir}/package.log",
                         "#{base_dir}/package-build.log"])
                end
            end

            describe "#resolve_package" do
                it "raises CLIInvalidArguments if there are no matches" do
                    cli.should_receive(:find_packages).and_return([])
                    cli.should_receive(:find_packages_with_directory_shortnames).
                        and_return([])
                    e = assert_raises(CLIInvalidArguments) do
                        cli.resolve_package('does/not/match')
                    end
                    assert_equal "cannot find 'does/not/match' in the current autoproj installation",
                        e.message
                end
                describe "exact package resolution" do
                    it "returns a exactly resolved packages" do
                        cli.should_receive(:find_packages).
                            with(selection = flexmock).
                            and_return([pkg = flexmock(srcdir: 'usr/local/dir')])
                        cli.should_receive(:find_packages_with_directory_shortnames).never
                        assert_equal pkg, cli.resolve_package(selection)
                    end
                    it "raises CLIAmbiguousArguments if find_packages returns more than one match" do
                        cli.should_receive(:find_packages).
                            with(selection = flexmock).
                            and_return([flexmock(name: 'pkg0', srcdir: ''), flexmock(name: 'pkg1', srcdir: '')])
                        e = assert_raises(CLIAmbiguousArguments) do
                            cli.resolve_package(selection)
                        end
                        assert_equal "multiple packages match '#{selection}' in the current autoproj installation: pkg0, pkg1", e.message
                    end
                    it "disambiguates the result by filtering on the source presence" do
                        cli.should_receive(:find_packages).
                            with(selection = flexmock).
                            and_return([
                                pkg = flexmock(name: 'pkg0', srcdir: '/pkg0'),
                                flexmock(name: 'pkg1', srcdir: '/pkg1')
                            ])
                        flexmock(File).should_receive(:directory?).and_return { |d| d == '/pkg0' }
                        assert_equal pkg, cli.resolve_package(selection)
                    end

                    describe "package resolution by category prefix" do
                        before do
                            cli.should_receive(:find_packages).and_return([])
                        end
                        it "attempts to resolve by category prefix if the exact match returns nothing" do
                            cli.should_receive(:find_packages_with_directory_shortnames).
                                with(selection = flexmock).
                                once.and_return([pkg = flexmock(srcdir: 'usr/local/dir')])
                            assert_equal pkg, cli.resolve_package(selection)
                        end
                        it "raises CLIAmbiguousArguments if it returns more than one match" do
                            cli.should_receive(:find_packages_with_directory_shortnames).
                                with(selection = flexmock).
                                and_return([flexmock(name: 'pkg0', srcdir: ''), flexmock(name: 'pkg1', srcdir: '')])
                            e = assert_raises(CLIAmbiguousArguments) do
                                cli.resolve_package(selection)
                            end
                            assert_equal "multiple packages match '#{selection}' in the current autoproj installation: pkg0, pkg1", e.message
                        end
                        it "disambiguates the result by filtering on the source presence" do
                            cli.should_receive(:find_packages_with_directory_shortnames).
                                with(selection = flexmock).
                                and_return([
                                    pkg = flexmock(name: 'pkg0', srcdir: '/pkg0'),
                                    flexmock(name: 'pkg1', srcdir: '/pkg1')
                                ])
                            flexmock(File).should_receive(:directory?).and_return { |d| d == '/pkg0' }
                            assert_equal pkg, cli.resolve_package(selection)
                        end
                    end
                end
            end
        end
    end
end

