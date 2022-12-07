module Autoproj
    module Ops
        class Cache
            attr_reader :cache_dir
            attr_reader :manifest

            def initialize(cache_dir, ws)
                @cache_dir = cache_dir
                @ws = ws
                @manifest = ws.manifest
            end

            def with_retry(count)
                (count + 1).times do |i|
                    break yield
                rescue Autobuild::SubcommandFailed
                    if i == count
                        raise
                    else
                        Autobuild.message "  failed, retrying (#{i}/#{count})"
                    end
                end
            end

            def git_cache_dir
                File.join(cache_dir, "git")
            end

            def cache_git(pkg, checkout_only: false)
                pkg.importdir = File.join(git_cache_dir, pkg.name)
                return if checkout_only && File.directory?(pkg.importdir)

                pkg.importer.local_branch = nil
                pkg.importer.remote_branch = nil
                pkg.importer.remote_name = "autobuild"

                unless File.directory?(pkg.importdir)
                    FileUtils.mkdir_p File.dirname(pkg.importdir)
                    Autobuild::Subprocess.run(
                        "autoproj-cache", "import", Autobuild.tool(:git),
                        "--git-dir", pkg.importdir, "init", "--bare"
                    )
                end
                pkg.importer.update_remotes_configuration(pkg, only_local: false)

                with_retry(10) do
                    Autobuild::Subprocess.run(
                        "autoproj-cache", :import, Autobuild.tool("git"),
                        "--git-dir", pkg.importdir, "remote", "update", "autobuild"
                    )
                end
                with_retry(10) do
                    Autobuild::Subprocess.run(
                        "autoproj-cache", :import, Autobuild.tool("git"),
                        "--git-dir", pkg.importdir, "fetch", "autobuild", "--tags"
                    )
                end
                Autobuild::Subprocess.run(
                    "autoproj-cache", :import, Autobuild.tool("git"),
                    "--git-dir", pkg.importdir, "gc", "--prune=all"
                )
            end

            def archive_cache_dir
                File.join(cache_dir, "archives")
            end

            def cache_archive(pkg)
                pkg.importer.cachedir = archive_cache_dir
                with_retry(10) do
                    pkg.importer.update_cache(pkg)
                end
            end

            def create_or_update(*package_names, all: true, keep_going: false,
                checkout_only: false)
                FileUtils.mkdir_p cache_dir

                packages =
                    if package_names.empty?
                        if all
                            manifest.each_autobuild_package
                        else
                            manifest.all_selected_source_packages.map(&:autobuild)
                        end
                    else
                        package_names.map do |name|
                            if (pkg = manifest.find_autobuild_package(name))
                                pkg
                            else
                                raise PackageNotFound, "no package named #{name}"
                            end
                        end
                    end

                packages = packages.sort_by(&:name)

                total = packages.size
                Autoproj.message "Handling #{total} packages"
                packages.each_with_index do |pkg, i|
                    # No need to process this one, it is uses another package's
                    # import
                    next if pkg.srcdir != pkg.importdir

                    begin
                        case pkg.importer
                        when Autobuild::Git
                            Autoproj.message(
                                "  [#{i}/#{total}] caching #{pkg.name} (git)"
                            )
                            cache_git(pkg, checkout_only: checkout_only)
                        when Autobuild::ArchiveImporter
                            Autoproj.message(
                                "  [#{i}/#{total}] caching #{pkg.name} (archive)"
                            )
                            cache_archive(pkg)
                        else
                            Autoproj.message(
                                "  [#{i}/#{total}] not caching #{pkg.name} "\
                                "(cannot cache #{pkg.importer.class})"
                            )
                        end
                    rescue Interrupt
                        raise
                    rescue ::Exception => e
                        raise unless keep_going

                        pkg.error "       failed to cache #{pkg.name}, "\
                                  "but going on as requested"
                        lines = e.to_s.split('\n')
                        lines = e.message.split('\n') if lines.empty?
                        lines = ["unknown error"] if lines.empty?
                        pkg.message(lines.shift, :red, :bold)
                        lines.each do |line|
                            pkg.message(line)
                        end
                        nil
                    end
                end
            end

            def gems_cache_dir
                File.join(cache_dir, "package_managers", "gem")
            end

            def create_or_update_gems(keep_going: true, compile_force: false, compile: [])
                # Note: this might directly copy into the cache directoy, and
                # we support it later
                cache_dir = File.join(@ws.prefix_dir, "gems", "vendor", "cache")
                PackageManagers::BundlerManager.run_bundler(
                    @ws, "cache"
                )

                FileUtils.mkdir_p(gems_cache_dir) unless File.exist?(gems_cache_dir)

                needs_copy =
                    if File.exist?(cache_dir)
                        real_cache_dir = File.realpath(cache_dir)
                        real_target_dir = File.realpath(gems_cache_dir)
                        (real_cache_dir != real_target_dir)
                    end

                synchronize_gems_cache_dirs(real_cache_dir, real_target_dir) if needs_copy

                platform_suffix = "-#{Gem::Platform.local}.gem"
                failed = []
                compile.each do |gem_name, artifacts: []|
                    Dir.glob(File.join(cache_dir, "#{gem_name}*.gem")) do |gem|
                        next unless /^#{gem_name}-\d/.match?(gem_name)
                        next if gem.end_with?(platform_suffix)

                        gem_basename = File.basename(gem, ".gem")
                        expected_platform_gem = File.join(
                            real_target_dir, "#{gem_basename}#{platform_suffix}"
                        )
                        next if !compile_force && File.file?(expected_platform_gem)

                        begin
                            compile_gem(
                                gem, artifacts: artifacts, output: real_target_dir
                            )
                        rescue CompilationFailed
                            unless keep_going
                                raise CompilationFailed, "#{gem} failed to compile"
                            end

                            failed << gem
                        end
                    end
                end

                unless failed.empty?
                    raise CompilationFailed, "#{failed.sort.join(', ')} failed to compile"
                end
            end

            class CompilationFailed < RuntimeError; end

            def synchronize_gems_cache_dirs(source, target)
                Dir.glob(File.join(source, "*.gem")) do |source_file|
                    basename = File.basename(source_file)
                    target_file = File.join(target, basename)
                    next if File.file?(target_file)

                    Autoproj.message "gems: caching #{basename}"
                    FileUtils.cp source_file, target_file
                end
            end

            def guess_gem_program
                return Autobuild.programs["gem"] if Autobuild.programs["gem"]

                ruby_bin = RbConfig::CONFIG["RUBY_INSTALL_NAME"]
                ruby_bindir = RbConfig::CONFIG["bindir"]

                candidates = ["gem"]
                candidates << "gem#{$1}" if ruby_bin =~ /^ruby(.+)$/

                candidates.each do |gem_name|
                    if File.file?(gem_full_path = File.join(ruby_bindir, gem_name))
                        Autobuild.programs["gem"] = gem_full_path
                        return Autobuild.programs["gem"]
                    end
                end

                raise ArgumentError,
                      "cannot find a gem program (tried "\
                      "#{candidates.sort.join(', ')} in #{ruby_bindir})"
            end

            private def compile_gem(gem_path, output:, artifacts: [])
                artifacts = artifacts.flat_map do |include, n|
                    if include
                        ["--include", n]
                    else
                        ["--exclude", n]
                    end
                end
                unless system(Autobuild.tool("ruby"), "-S", guess_gem_program,
                              "compile", "--output", output, *artifacts, gem_path)
                    raise CompilationFailed, "#{gem_path} failed to compile"
                end
            end
        end
    end
end
