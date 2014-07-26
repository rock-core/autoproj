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

                Autoproj.message "  caching #{pkg.name} (git)"
                if !File.directory?(pkg.importdir)
                    FileUtils.mkdir_p File.dirname(pkg.importdir)
                    Autobuild::Subprocess.run("autoproj-cache", "import", Autobuild.tool(:git), "--git-dir", pkg.importdir, 'init', "--bare")
                end
                pkg.importer.update_remotes_configuration(pkg, 'autoproj-cache')

                with_retry(10) do
                    Autobuild::Subprocess.run('autoproj-cache', :import, Autobuild.tool('git'), '--git-dir', pkg.importdir, 'remote', 'update', 'autobuild')
                end
                Autobuild::Subprocess.run('autoproj-cache', :import, Autobuild.tool('git'), '--git-dir', pkg.importdir, 'gc', '--prune=all', '--aggressive')
            end

            def archive_cache_dir
                File.join(cache_dir, 'archives')
            end

            def cache_archive(pkg)
                Autoproj.message "  caching #{pkg.name} (archive)"
                pkg.importer.cachedir = archive_cache_dir
                with_retry(10) do
                    pkg.importer.update_cache(pkg)
                end
            end

            def create_or_update
                FileUtils.mkdir_p cache_dir

                manifest.each_autobuild_package do |pkg|
                    if pkg.importer.kind_of?(Autobuild::Git)
                        cache_git(pkg)
                    elsif pkg.importer.kind_of?(Autobuild::ArchiveImporter)
                        cache_archive(pkg)
                    end
                end
            end
        end
    end
end

