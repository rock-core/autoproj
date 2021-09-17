require "autoproj/cli/inspection_tool"
require "tty-spinner"

module Autoproj
    module CLI
        class Status < InspectionTool
            def validate_options(packages, options)
                packages, options = super
                options[:progress] = Autobuild.progress_display_enabled?
                options[:deps] = false if options[:no_deps_shortcut]
                options[:deps] = true if options[:deps].nil? && packages.empty?
                [packages, options]
            end

            def run(user_selection, options = Hash.new)
                initialize_and_load(mainline: options[:mainline])
                packages, *, config_selected = finalize_setup(
                    user_selection,
                    recursive: options[:deps]
                )

                if options[:config].nil?
                    options[:config] = user_selection.empty? || config_selected
                end

                if packages.empty?
                    Autoproj.error "no packages or OS packages match #{user_selection.join(' ')}"
                    return
                end

                if !options.has_key?(:parallel) && options[:only_local]
                    options[:parallel] = 1
                else
                    options[:parallel] ||= ws.config.parallel_import_level
                end

                if options[:config]
                    pkg_sets = ws.manifest.each_package_set.to_a
                    unless pkg_sets.empty?
                        Autoproj.message("autoproj: displaying status of configuration", :bold)
                        display_status(
                            pkg_sets,
                            parallel: options[:parallel],
                            snapshot: options[:snapshot],
                            only_local: options[:only_local],
                            progress: options[:progress]
                        )

                        STDERR.puts
                    end
                end

                Autoproj.message("autoproj: displaying status of packages", :bold)
                packages = packages.sort.map do |pkg_name|
                    ws.manifest.find_package_definition(pkg_name)
                end
                display_status(
                    packages,
                    parallel: options[:parallel],
                    snapshot: options[:snapshot],
                    only_local: options[:only_local],
                    progress: options[:progress]
                )
            end

            def snapshot_overrides_vcs?(importer, vcs, snapshot)
                if importer.respond_to?(:snapshot_overrides?)
                    importer.snapshot_overrides?(snapshot)
                else
                    vcs = vcs.to_hash
                    snapshot.any? { |k, v| vcs[k] != v }
                end
            end

            def self.report_exception(package_status, msg, e)
                package_status.msg << Autoproj.color("  #{msg} (#{e})", :red)
                if Autobuild.debug
                    package_status.msg.concat(e.backtrace.map do |line|
                        Autoproj.color("    #{line}", :red)
                    end)
                end
            end

            PackageStatus = Struct.new :msg, :sync, :unexpected, :uncommitted, :local, :remote
            def self.status_of_package(package_description, only_local: false, snapshot: false)
                pkg = package_description.autobuild
                importer = pkg.importer
                package_status = PackageStatus.new(Array.new, false, false, false, false)
                if !importer
                    package_status.msg << Autoproj.color("  is a local-only package (no VCS)", :bold, :red)
                elsif !importer.respond_to?(:status)
                    package_status.msg << Autoproj.color("  the #{importer.class.name.gsub(/.*::/, '')} importer does not support status display", :bold, :red)
                elsif !File.directory?(pkg.srcdir)
                    package_status.msg << Autoproj.color("  is not imported yet", :magenta)
                else
                    begin status = importer.status(pkg, only_local: only_local)
                    rescue StandardError => e
                        report_exception(package_status, "failed to fetch status information", e)
                        return package_status
                    end

                    snapshot_useful = [Autobuild::Importer::Status::ADVANCED, Autobuild::Importer::Status::NEEDS_MERGE]
                                      .include?(status.status)
                    if snapshot && snapshot_useful && importer.respond_to?(:snapshot)
                        snapshot_version =
                            begin importer.snapshot(pkg, nil, exact_state: false, only_local: only_local)
                            rescue Autobuild::PackageException
                                Hash.new
                            rescue StandardError => e
                                report_exception(package_status, "failed to fetch snapshotting information", e)
                                return package_status
                            end
                        if snapshot_overrides_vcs?(importer, package_description.vcs, snapshot_version)
                            non_nil_values = snapshot_version.delete_if { |k, v| !v }
                            package_status.msg << Autoproj.color("  found configuration that contains all local changes: #{non_nil_values.sort_by(&:first).map { |k, v| "#{k}: #{v}" }.join(', ')}", :bright_green)
                            package_status.msg << Autoproj.color("  consider adding this to your overrides, or use autoproj versions to do it for you", :bright_green)
                            if snapshot
                                importer.relocate(importer.repository, snapshot_version)
                            end
                        end
                    end

                    status.unexpected_working_copy_state.each do |msg|
                        package_status.unexpected = true
                        package_status.msg << Autoproj.color("  #{msg}", :red, :bold)
                    end

                    if status.uncommitted_code
                        package_status.msg << Autoproj.color("  contains uncommitted modifications", :red)
                        package_status.uncommitted = true
                    end

                    case status.status
                    when Autobuild::Importer::Status::UP_TO_DATE
                        package_status.sync = true
                    when Autobuild::Importer::Status::ADVANCED
                        package_status.local = true
                        package_status.msg << Autoproj.color("  local contains #{status.local_commits.size} commit that remote does not have:", :blue)
                        status.local_commits.each do |line|
                            package_status.msg << Autoproj.color("    #{line}", :blue)
                        end
                    when Autobuild::Importer::Status::SIMPLE_UPDATE
                        package_status.remote = true
                        package_status.msg << Autoproj.color("  remote contains #{status.remote_commits.size} commit that local does not have:", :magenta)
                        status.remote_commits.each do |line|
                            package_status.msg << Autoproj.color("    #{line}", :magenta)
                        end
                    when Autobuild::Importer::Status::NEEDS_MERGE
                        package_status.local  = true
                        package_status.remote = true
                        package_status.msg << "  local and remote have diverged with respectively #{status.local_commits.size} and #{status.remote_commits.size} commits each"
                        package_status.msg << Autoproj.color("  -- local commits --", :blue)
                        status.local_commits.each do |line|
                            package_status.msg << Autoproj.color("   #{line}", :blue)
                        end
                        package_status.msg << Autoproj.color("  -- remote commits --", :magenta)
                        status.remote_commits.each do |line|
                            package_status.msg << Autoproj.color("   #{line}", :magenta)
                        end
                    end
                end
                package_status
            end

            def each_package_status(
                packages,
                parallel: ws.config.parallel_import_level,
                snapshot: false, only_local: false, progress: nil
            )
                return enum_for(__method__) unless block_given?

                result = StatusResult.new

                executor = Concurrent::FixedThreadPool.new(parallel, max_length: 0)
                interactive, noninteractive =
                    packages.partition { |pkg| pkg.autobuild.importer&.interactive? }
                noninteractive = noninteractive.map do |pkg|
                    future = Concurrent::Promises.future_on(executor) do
                        Status.status_of_package(
                            pkg, snapshot: snapshot, only_local: only_local
                        )
                    end
                    [pkg, future]
                end

                (noninteractive + interactive).each do |pkg, future|
                    if future
                        if progress
                            wait_timeout = 1
                            loop do
                                future.wait!(wait_timeout)
                                if future.resolved?
                                    break
                                else
                                    wait_timeout = 0.2
                                    progress.call(pkg)
                                end
                            end
                        end

                        unless (status = future.value)
                            raise future.reason
                        end
                    else
                        status = Status.status_of_package(
                            pkg, snapshot: snapshot, only_local: only_local
                        )
                    end

                    result.uncommitted ||= status.uncommitted
                    result.local       ||= status.local
                    result.remote      ||= status.remote
                    yield(pkg, status)
                end
                result
            rescue Interrupt
                Autoproj.warn "Interrupted, waiting for pending jobs to finish"
                raise
            rescue Exception => e
                Autoproj.error "internal error (#{e.class}): #{e}, waiting for pending jobs to finish"
                raise
            ensure
                executor.shutdown
                executor.wait_for_termination
            end

            StatusResult = Struct.new :uncommitted, :local, :remote
            def display_status(packages, parallel: ws.config.parallel_import_level, snapshot: false, only_local: false, progress: true)
                sync_packages = ""
                spinner = nil

                if progress
                    progress = lambda do |pkg|
                        unless spinner
                            unless sync_packages.empty?
                                Autoproj.message("#{sync_packages}: #{Autoproj.color('local and remote are in sync', :green)}")
                                sync_packages = ""
                            end

                            spinner = TTY::Spinner.new("[:spinner] #{pkg.name}", clear: true)
                        end
                        spinner.spin
                    end
                end

                result = each_package_status(packages, only_local: only_local, parallel: parallel, progress: progress) do |pkg, status|
                    if spinner
                        spinner.stop
                        spinner = nil
                    end

                    pkg_name = pkg.name
                    if status.sync && status.msg.empty?
                        if sync_packages.size > 80
                            Autoproj.message "#{sync_packages},"
                            sync_packages = ""
                        end
                        msg = if sync_packages.empty?
                                  pkg_name
                              else
                                  ", #{pkg_name}"
                              end
                        STDERR.print msg
                        sync_packages = "#{sync_packages}#{msg}"
                        next
                    end

                    unless sync_packages.empty?
                        Autoproj.message("#{sync_packages}: #{Autoproj.color('local and remote are in sync', :green)}")
                        sync_packages = ""
                    end

                    STDERR.print

                    if status.msg.size == 1
                        Autoproj.message "#{pkg_name}: #{status.msg.first}"
                    else
                        Autoproj.message "#{pkg_name}:"
                        status.msg.each do |l|
                            Autoproj.message l
                        end
                    end
                end
                unless sync_packages.empty?
                    Autoproj.message("#{sync_packages}: #{Autoproj.color('local and remote are in sync', :green)}")
                end
                result
            end
        end
    end
end
