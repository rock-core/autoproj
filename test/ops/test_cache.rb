require "autoproj/test"
require "autoproj/ops/cache"

module Autoproj
    module Ops
        describe Cache do
            before do
                @cache_dir = make_tmpdir
                @ws = ws_create
                @ops = Cache.new(@cache_dir, @ws)
                flexmock(@ops)
                flexmock(Autoproj)
            end

            describe "#cache_git" do
                before do
                    root = make_tmpdir
                    system("tar", "xzf", data_path("cache-git.tar.gz"),
                           "-C", root)
                    @gitrepo_path = File.join(root, "cache-git")
                end

                it "does nothing if checkout_only is set and the target dir exists" do
                    FileUtils.mkdir_p File.join(@cache_dir, "git", "pkg")
                    pkg = Struct.new(:name, :importdir).new("pkg")
                    flexmock(Autobuild::Subprocess).should_receive(:run).never
                    @ops.cache_git(pkg, checkout_only: true)
                end

                it "fetches all refs and tags" do
                    importer = Autobuild.git @gitrepo_path
                    pkg = Autobuild::Package.new "pkg"
                    pkg.importer = importer
                    @ops.cache_git(pkg)

                    # Try resolving known refs to make sure it got updated
                    importer.rev_parse(pkg, "refs/remotes/autobuild/master")
                    importer.rev_parse(pkg, "refs/remotes/autobuild/some-branch")
                    importer.rev_parse(pkg, "some-tag")
                end

                it "updates an existing cache dir" do
                    importer = Autobuild.git @gitrepo_path
                    pkg = Autobuild::Package.new "pkg"
                    pkg.importer = importer
                    @ops.cache_git(pkg)

                    importer.run_git_bare(pkg, "tag", "-d", "some-tag")
                    @ops.cache_git(pkg)
                    importer.rev_parse(pkg, "some-tag")
                end
            end

            describe "#create_or_update" do
                before do
                    root = make_tmpdir
                    system("tar", "xzf", data_path("cache-git.tar.gz"),
                           "-C", root)
                    @gitrepo_path = File.join(root, "cache-git")

                    @pkg = ws_define_package "cmake", "pkg"
                end

                it "raises if given an invalid package name" do
                    assert_raises(PackageNotFound) do
                        @ops.create_or_update("invalid")
                    end
                end

                it "resolves package names if given as argument" do
                    (1..5).each do |i|
                        pkg = ws_define_package "cmake", "pkg#{i}"
                        pkg.autobuild.importer = Autobuild.git(@gitrepo_path)

                        expectation = @ops
                                      .should_receive(:cache_git)
                                      .with(pkg.autobuild, checkout_only: false)
                        if [2, 3].include?(i)
                            expectation.once
                        else
                            expectation.never
                        end
                    end

                    Autoproj.should_receive(:message)
                    @ops.create_or_update("pkg2", "pkg3")
                end

                it "passes an error if keep_going is false" do
                    pkg0 = @pkg
                    pkg1 = ws_define_package "cmake", "pkg1"
                    pkg0.autobuild.importer = Autobuild.git(@gitrepo_path)
                    pkg1.autobuild.importer = Autobuild.git(@gitrepo_path)

                    @ops.should_receive(:cache_git)
                        .with(pkg0.autobuild, checkout_only: false).once
                        .and_raise(RuntimeError)
                    @ops.should_receive(:cache_git)
                        .with(pkg1.autobuild, checkout_only: false).never
                    Autoproj.should_receive(:message)
                    assert_raises(RuntimeError) do
                        @ops.create_or_update
                    end
                end

                it "continues on error if keep_going is true" do
                    pkg0 = @pkg
                    pkg1 = ws_define_package "cmake", "pkg1"
                    pkg0.autobuild.importer = Autobuild.git(@gitrepo_path)
                    pkg1.autobuild.importer = Autobuild.git(@gitrepo_path)

                    @ops.should_receive(:cache_git)
                        .with(pkg0.autobuild, checkout_only: false).once
                        .globally.ordered.and_raise(RuntimeError)
                    @ops.should_receive(:cache_git)
                        .with(pkg1.autobuild, checkout_only: false).once
                        .globally.ordered
                    Autoproj.should_receive(:message)
                    @ops.create_or_update(keep_going: true)
                end

                it "caches a package with a git importer" do
                    @pkg.autobuild.importer = Autobuild.git(@gitrepo_path)
                    @ops.should_receive(:cache_git)
                        .with(@pkg.autobuild, checkout_only: false).once
                    Autoproj.should_receive(:message)
                            .with(/caching pkg \(git\)/).once
                    Autoproj.should_receive(:message)
                    @ops.create_or_update
                end

                it "caches a package with an archive importer" do
                    @pkg.autobuild.importer = Autobuild.archive("file:///some/path")
                    @ops.should_receive(:cache_archive)
                        .with(@pkg.autobuild).once
                    Autoproj.should_receive(:message)
                            .with(/caching pkg \(archive\)/).once
                    Autoproj.should_receive(:message)
                    @ops.create_or_update
                end

                it "skips other types of importers" do
                    @pkg.autobuild.importer = Autobuild.svn("file:///some/path")
                    Autoproj.should_receive(:message)
                            .with(/not caching pkg/).once
                    Autoproj.should_receive(:message)

                    @ops.create_or_update
                end
            end

            describe "#guess_gem_program" do
                before do
                    @bindir = RbConfig::CONFIG["bindir"]
                    @ruby_install_name = RbConfig::CONFIG["RUBY_INSTALL_NAME"]
                end

                after do
                    RbConfig::CONFIG["bindir"] = @bindir
                    RbConfig::CONFIG["RUBY_INSTALL_NAME"] = @ruby_install_name
                    Autobuild.programs.delete("gem")
                end

                it "autodetects the gem program on the machine running the tests" do
                    detected = @ops.guess_gem_program
                    assert_match(/gem/, detected)
                    assert File.executable?(detected)
                end

                it "sets the program to the detected program" do
                    detected = @ops.guess_gem_program
                    assert_equal detected, Autobuild.tool("gem")
                end

                it 'looks for "gem" in ruby\'s bindir' do
                    RbConfig::CONFIG["bindir"] = dir = make_tmpdir
                    FileUtils.touch File.join(dir, "gem")
                    assert_equal File.join(dir, "gem"), @ops.guess_gem_program
                end

                it 'looks for "gem$SUFFIX" in ruby\'s bindir when ruby was installed with a suffix' do
                    RbConfig::CONFIG["bindir"] = dir = make_tmpdir
                    RbConfig::CONFIG["RUBY_INSTALL_NAME"] = "ruby-withsomesuffix"
                    FileUtils.touch File.join(dir, "gem-withsomesuffix")
                    assert_equal File.join(dir, "gem-withsomesuffix"), @ops.guess_gem_program
                end

                it "uses the value in programs if there is one" do
                    Autobuild.programs["gem"] = "some value"
                    assert_equal "some value", @ops.guess_gem_program
                end
            end

            describe "#create_or_update_gems" do
                before do
                    flexmock(Autobuild).should_receive(:tool).with("ruby").and_return("myruby")
                    flexmock(@ops).should_receive(:guess_gem_program).and_return("mygem")
                    @target_dir = File.join(@cache_dir, "package_managers", "gem")
                    @cache_dir = File.join(@ws.prefix_dir, "gems", "vendor", "cache")
                    flexmock(PackageManagers::BundlerManager)
                        .should_receive(:run_bundler).by_default
                end

                it "synchronizes the cache dir if it is not a symlink to the target dir" do
                    PackageManagers::BundlerManager
                        .should_receive(:run_bundler).with(@ws, "cache").once
                        .and_return { FileUtils.mkdir_p(@cache_dir) }
                    @ops.should_receive(:synchronize_gems_cache_dirs)
                        .with(@cache_dir, @target_dir).once
                    @ops.create_or_update_gems
                end

                it "does not synchronize the cache dir if it is a symlink to the target dir" do
                    FileUtils.mkdir_p File.dirname(@cache_dir)
                    FileUtils.mkdir_p @target_dir
                    FileUtils.ln_s @target_dir, @cache_dir
                    @ops.should_receive(:synchronize_gems_cache_dirs)
                        .with(@cache_dir, @target_dir).never
                    @ops.create_or_update_gems
                end

                it "compiles requested gems if they are not present" do
                    FileUtils.mkdir_p @cache_dir
                    FileUtils.touch(
                        File.join(@cache_dir, "gemname.gem")
                    )
                    @ops.should_receive(:system).explicitly.once
                        .with("myruby", "-S", "mygem", "compile",
                              "--output", @target_dir, "#{@cache_dir}/gemname.gem")
                        .and_return(true)
                    @ops.create_or_update_gems(compile: ["gemname"])
                end

                it "passes the artifacts argument" do
                    FileUtils.mkdir_p @cache_dir
                    FileUtils.touch(
                        File.join(@cache_dir, "gemname.gem")
                    )
                    @ops.should_receive(:system).explicitly.once
                        .with("myruby", "-S", "mygem", "compile",
                              "--output", @target_dir,
                              "--include", "some/lib",
                              "--exclude", "some/dir",
                              "#{@cache_dir}/gemname.gem")
                        .and_return(true)
                    @ops.create_or_update_gems(
                        compile: [
                            [
                                "gemname",
                                artifacts: [[true, "some/lib"], [false, "some/dir"]]
                            ]
                        ]
                    )
                end

                it "skips already compiled gems" do
                    FileUtils.mkdir_p @cache_dir
                    FileUtils.mkdir_p @target_dir
                    FileUtils.touch(File.join(@cache_dir, "gemname.gem"))
                    FileUtils.touch(
                        File.join(@target_dir, "gemname-#{Gem::Platform.local}.gem")
                    )
                    @ops.should_receive(:system).explicitly.never
                    @ops.create_or_update_gems(compile: ["gemname"])
                end

                it "recompiles existing gems if compile_force is set" do
                    FileUtils.mkdir_p @cache_dir
                    FileUtils.mkdir_p @target_dir
                    FileUtils.touch(File.join(@cache_dir, "gemname.gem"))
                    FileUtils.touch(
                        File.join(@target_dir, "gemname-#{Gem::Platform.local}.gem")
                    )
                    @ops.should_receive(:system).explicitly.once
                        .with("myruby", "-S", "mygem", "compile",
                              "--output", @target_dir, "#{@cache_dir}/gemname.gem")
                        .and_return(true)
                    @ops.create_or_update_gems(compile: ["gemname"], compile_force: true)
                end

                it "stops at first error if keep_going is false" do
                    FileUtils.mkdir_p @cache_dir
                    FileUtils.touch(File.join(@cache_dir, "gem0.gem"))
                    FileUtils.touch(File.join(@cache_dir, "gem1.gem"))
                    @ops.should_receive(:system).explicitly.once
                        .and_return(false)
                    e = assert_raises(Cache::CompilationFailed) do
                        @ops.create_or_update_gems(keep_going: false, compile: %w[gem0 gem1])
                    end
                    assert_equal "#{@cache_dir}/gem0.gem failed to compile", e.message
                end

                it "continues installation after error if keep_going is true, but reports the errors at the end" do
                    FileUtils.mkdir_p @cache_dir
                    FileUtils.touch(File.join(@cache_dir, "gem0.gem"))
                    FileUtils.touch(File.join(@cache_dir, "gem1.gem"))
                    @ops.should_receive(:system).explicitly.once
                        .and_return(false).globally.ordered
                    @ops.should_receive(:system).explicitly.once
                        .and_return(true).globally.ordered
                    e = assert_raises(Cache::CompilationFailed) do
                        @ops.create_or_update_gems(compile: %w[gem0 gem1])
                    end
                    assert_equal "#{@cache_dir}/gem0.gem failed to compile", e.message
                end

                it "does not attempt to compile platform gems present in the source dir" do
                    FileUtils.mkdir_p @cache_dir
                    FileUtils.touch(
                        File.join(@cache_dir, "gemname-#{Gem::Platform.local}.gem")
                    )
                    @ops.should_receive(:system).explicitly.never
                    @ops.create_or_update_gems(compile: ["gemname"])
                end
            end

            describe "#synchronize_gems_cache_dirs" do
                before do
                    @target_dir = make_tmpdir
                    FileUtils.touch File.join(@cache_dir, "gem0.gem")
                    FileUtils.touch File.join(@cache_dir, "gem1.gem")
                end

                it "copies gem files from source to target" do
                    @ops.synchronize_gems_cache_dirs(@cache_dir, @target_dir)
                    assert File.file?(File.join(@target_dir, "gem0.gem"))
                    assert File.file?(File.join(@target_dir, "gem1.gem"))
                end

                it "ignores non-gem files" do
                    FileUtils.touch File.join(@cache_dir, "somefile")
                    @ops.synchronize_gems_cache_dirs(@cache_dir, @target_dir)
                    refute File.file?(File.join(@target_dir, "somefile"))
                end

                it "skips files that already exist" do
                    FileUtils.touch File.join(@target_dir, "gem0.gem")
                    FileUtils.touch File.join(@target_dir, "gem1.gem")
                    flexmock(FileUtils).should_receive(:cp).never
                    @ops.synchronize_gems_cache_dirs(@cache_dir, @target_dir)
                end
            end
        end
    end
end
