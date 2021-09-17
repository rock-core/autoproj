require "rbconfig"
require "autoproj/cli/inspection_tool"
require "autoproj/ops/watch"
module Autoproj
    module CLI
        class Watch < InspectionTool
            attr_reader :notifier

            def initialize(*args)
                super(*args)
                @show_events = false
            end

            def validate_options(unused, options = {})
                _, options = super(unused, options)
                @show_events = options[:show_events]
                nil
            end

            def show_events?
                @show_events
            end

            def update_workspace
                initialize_and_load

                source_packages, = finalize_setup([])
                @source_packages_dirs = source_packages.map do |pkg_name|
                    ws.manifest.find_autobuild_package(pkg_name).srcdir
                end
                @pkg_sets_dirs = ws.manifest.each_package_set.map(&:raw_local_dir)
                export_env_sh(shell_helpers: ws.config.shell_helpers?)
            end

            def load_info_from_installation_manifest
                installation_manifest =
                    begin
                        Autoproj::InstallationManifest.from_workspace_root(ws.root_dir)
                    rescue ConfigError
                    end

                @source_packages_dirs = []
                @package_sets = []

                @source_packages_dirs = installation_manifest.each_package
                                                             .map(&:srcdir)
                @package_sets = installation_manifest.each_package_set
                                                     .map(&:raw_local_dir)
            end

            def callback
                Thread.new { notifier.stop }
            end

            def create_file_watcher(file)
                notifier.watch(file, :modify) do |e|
                    Autobuild.message "#{e.absolute_name} modified" if show_events?
                    callback
                end
            end

            def create_dir_watcher(dir, included_paths: [], excluded_paths: [], inotify_flags: [])
                strip_dir_range = ((dir.size + 1)..-1)
                notifier.watch(dir, :move, :create, :delete, :modify, :dont_follow, *inotify_flags) do |e|
                    file_name = e.absolute_name[strip_dir_range]
                    included = included_paths.empty? ||
                               included_paths.any? { |rx| rx === file_name }
                    included = !excluded_paths.any? { |rx| rx === file_name } if included
                    next unless included

                    Autobuild.message "#{e.absolute_name} changed" if show_events?
                    callback
                end
            end

            def create_src_pkg_watchers
                @source_packages_dirs.each do |pkg_srcdir|
                    next unless File.exist? pkg_srcdir

                    create_dir_watcher(pkg_srcdir, included_paths: ["manifest.xml", "package.xml"])

                    manifest_file = File.join(pkg_srcdir, "manifest.xml")
                    create_file_watcher(manifest_file) if File.exist? manifest_file
                    ros_manifest_file = File.join(pkg_srcdir, "package.xml")
                    if File.exist? ros_manifest_file
                        create_file_watcher(ros_manifest_file)
                    end
                end
            end

            def start_watchers
                create_file_watcher(ws.config.path)
                create_src_pkg_watchers
                create_dir_watcher(ws.config_dir,
                                   excluded_paths: [/(^|#{File::SEPARATOR})\./],
                                   inotify_flags: [:recursive])
                FileUtils.mkdir_p ws.remotes_dir
                create_dir_watcher(ws.remotes_dir,
                                   excluded_paths: [/(^|#{File::SEPARATOR})\./],
                                   inotify_flags: [:recursive])
            end

            def cleanup_notifier
                notifier.watchers.dup.each_value(&:close)
                notifier.close
            end

            def assert_watchers_available
                return if RbConfig::CONFIG["target_os"] =~ /linux/

                puts "error: Workspace watching not available on this platform"
                exit 1
            end

            def setup_notifier
                assert_watchers_available

                require "rb-inotify"
                @notifier = INotify::Notifier.new
            end

            def cleanup
                Ops.watch_cleanup_marker(@marker_io) if @marker_io
                cleanup_notifier if @notifier
            end

            def restart
                cleanup
                args = []
                args << "--show-events" if show_events?
                exec($PROGRAM_NAME, "watch", *args)
            end

            def run(**)
                @marker_io = Ops.watch_create_marker(ws.root_dir)
                begin
                    update_workspace
                rescue Exception => e
                    puts "ERROR: #{e.message}"
                    load_info_from_installation_manifest
                end
                setup_notifier
                start_watchers

                puts "Watching workspace, press ^C to quit..."
                notifier.run

                puts "Workspace changed..."
                restart
            rescue Interrupt
                puts "Exiting..."
            ensure
                cleanup
            end
        end
    end
end
