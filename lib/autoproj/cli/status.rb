require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Status < InspectionTool
            def validate_options(packages, options)
                packages, options = super
                if options[:dep].nil? && packages.empty?
                    options[:dep] = true
                end
                return packages, options
            end

            def run(user_selection, options = Hash.new)
                initialize_and_load(mainline: options[:mainline])
                packages, *, config_selected = finalize_setup(
                    user_selection,
                    recursive: options[:dep],
                    ignore_non_imported_packages: true)

                if options[:config].nil?
                    options[:config] = user_selection.empty? || config_selected
                end

                if packages.empty?
                    Autoproj.error "no packages or OS packages match #{user_selection.join(" ")}"
                    return
                end

                if options[:config]
                    pkg_sets = ws.manifest.each_package_set.map(&:create_autobuild_package)
                    if !pkg_sets.empty?
                        Autoproj.message("autoproj: displaying status of configuration", :bold)
                        display_status(pkg_sets, only_local: options[:only_local])
                        STDERR.puts
                    end
                end

                Autoproj.message("autoproj: displaying status of packages", :bold)
                packages = packages.sort.map do |pkg_name|
                    ws.manifest.find_autobuild_package(pkg_name)
                end
                display_status(packages, only_local: options[:only_local])
            end

            PackageStatus = Struct.new :msg, :sync, :uncommitted, :local, :remote
            def status_of_package(pkg, options = Hash.new)
                package_status = PackageStatus.new(Array.new, false, false, false, false)
                if !pkg.importer
                    package_status.msg << Autoproj.color("  is a local-only package (no VCS)", :bold, :red)
                elsif !pkg.importer.respond_to?(:status)
                    package_status.msg << Autoproj.color("  the #{pkg.importer.class.name.gsub(/.*::/, '')} importer does not support status display", :bold, :red)
                elsif !File.directory?(pkg.srcdir)
                    package_status.msg << Autoproj.color("  is not imported yet", :magenta)
                else
                    begin status = pkg.importer.status(pkg, options[:only_local])
                    rescue Interrupt
                        raise
                    rescue Exception => e
                        package_status.msg << Autoproj.color("  failed to fetch status information (#{e})", :red)
                        return package_status
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

            StatusResult = Struct.new :uncommitted, :local, :remote
            def display_status(packages, options = Hash.new)
                result = StatusResult.new

                executor = Concurrent::FixedThreadPool.new(ws.config.parallel_import_level, max_length: 0)
                interactive, noninteractive = packages.partition { |pkg| pkg.importer && pkg.importer.interactive? }
                noninteractive = noninteractive.map do |pkg|
                    [pkg, Concurrent::Future.execute(executor: executor) { status_of_package(pkg, only_local: options[:only_local]) }]
                end

                sync_packages = ""
                (noninteractive + interactive).each do |pkg, future|
                    if future 
                        if error = future.reason
                            raise error
                        end
                        status = future.value
                    else status = status_of_package(pkg, only_local: options[:only_local])
                    end

                    result.uncommitted ||= status.uncommitted
                    result.local       ||= status.local
                    result.remote      ||= status.remote

                    pkg_name = pkg.autoproj_name
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

                    if !sync_packages.empty?
                        Autoproj.message("#{sync_packages}: #{Autoproj.color("local and remote are in sync", :green)}")
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
                if !sync_packages.empty?
                    Autoproj.message("#{sync_packages}: #{Autoproj.color("local and remote are in sync", :green)}")
                end
                return result

            rescue Interrupt
                Autoproj.warn "Interrupted, waiting for pending jobs to finish"
            rescue Exception => e
                Autoproj.error "internal error: #{e}, waiting for pending jobs to finish"
                raise
            ensure
                executor.shutdown
                executor.wait_for_termination
            end

        end
    end
end

