module Autoproj
    module Ops
        class Cache
            attr_reader :cache_dir
            attr_reader :manifest

            def initialize(cache_dir, manifest)
                @cache_dir = cache_dir
                @manifest  = manifest
            end

            def with_retry(count)
                (count + 1).times do |i|
                    begin
                        break yield
                    rescue Autobuild::SubcommandFailed
                        if i == count
                            raise
                        else
                            Autobuild.message "  failed, retrying (#{i}/#{count})"
                        end
                    end
                end
            end

            def git_cache_dir
                File.join(cache_dir, 'git')
            end

            def cache_git(pkg)
                pkg.importdir = File.join(git_cache_dir, pkg.name)
                pkg.importer.local_branch = nil
                pkg.importer.remote_branch = nil
                pkg.importer.remote_name = 'autobuild'

                if !File.directory?(pkg.importdir)
                    FileUtils.mkdir_p File.dirname(pkg.importdir)
                    Autobuild::Subprocess.run("autoproj-cache", "import", Autobuild.tool(:git), "--git-dir", pkg.importdir, 'init', "--bare")
                end
                pkg.importer.update_remotes_configuration(pkg, 'autoproj-cache')

                with_retry(10) do
                    Autobuild::Subprocess.run('autoproj-cache', :import, Autobuild.tool('git'), '--git-dir', pkg.importdir, 'remote', 'update', 'autobuild')
                end
                Autobuild::Subprocess.run('autoproj-cache', :import, Autobuild.tool('git'), '--git-dir', pkg.importdir, 'gc', '--prune=all')
            end

            def archive_cache_dir
                File.join(cache_dir, 'archives')
            end

            def cache_archive(pkg)
                pkg.importer.cachedir = archive_cache_dir
                with_retry(10) do
                    pkg.importer.update_cache(pkg)
                end
            end

            def create_or_update
                FileUtils.mkdir_p cache_dir

                packages = manifest.each_autobuild_package.
                    sort_by(&:name)
                total = packages.size
                Autoproj.message "Handling #{total} packages"
                packages.each_with_index do |pkg, i|
                    case pkg.importer
                    when Autobuild::Git
                        Autoproj.message "  [#{i}/#{total}] caching #{pkg.name} (git)"
                        cache_git(pkg)
                    when Autobuild::ArchiveImporter
                        Autoproj.message "  [#{i}/#{total}] caching #{pkg.name} (archive)"
                        cache_archive(pkg)
                    else
                        Autoproj.message "  [#{i}/#{total}] not caching #{pkg.name} (cannot cache #{pkg.importer.class})"
                    end
                end
            end
        end
    end
end

