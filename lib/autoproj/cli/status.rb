require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Status < InspectionTool
            def run(selected_packages, options = Hash.new)
                selected_packages, config_selected =
                    normalize_command_line_package_selection(selected_packages)

                if options[:config].nil?
                    options[:config] = selected_packages.empty? || config_selected
                end

                packages, resolved_selection = resolve_selection(
                    ws.manifest,
                    selected_packages,
                    recursive: false,
                    ignore_non_imported_packages: true)
                if packages.empty?
                    Autoproj.error "no packages or OS packages match #{selected_packages.join(" ")}"
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

            StatusResult = Struct.new :uncommitted, :local, :remote
            def display_status(packages, options = Hash.new)
                result = StatusResult.new

                sync_packages = ""
                packages.each do |pkg|
                    lines = []

                    pkg_name = pkg.autoproj_name

                    if !pkg.importer
                        lines << Autoproj.color("  is a local-only package (no VCS)", :bold, :red)
                    elsif !pkg.importer.respond_to?(:status)
                        lines << Autoproj.color("  the #{pkg.importer.class.name.gsub(/.*::/, '')} importer does not support status display", :bold, :red)
                    elsif !File.directory?(pkg.srcdir)
                        lines << Autoproj.color("  is not imported yet", :magenta)
                    else
                        status = begin pkg.importer.status(pkg, options[:only_local])
                                 rescue Interrupt
                                     raise
                                 rescue Exception => e
                                     lines << Autoproj.color("  failed to fetch status information (#{e})", :red)
                                     nil
                                 end

                        if status
                            if status.uncommitted_code
                                lines << Autoproj.color("  contains uncommitted modifications", :red)
                                result.uncommitted = true
                            end

                            case status.status
                            when Autobuild::Importer::Status::UP_TO_DATE
                                if !status.uncommitted_code
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
                                else
                                    lines << Autoproj.color("  local and remote are in sync", :green)
                                end
                            when Autobuild::Importer::Status::ADVANCED
                                result.local = true
                                lines << Autoproj.color("  local contains #{status.local_commits.size} commit that remote does not have:", :blue)
                                status.local_commits.each do |line|
                                    lines << Autoproj.color("    #{line}", :blue)
                                end
                            when Autobuild::Importer::Status::SIMPLE_UPDATE
                                result.remote = true
                                lines << Autoproj.color("  remote contains #{status.remote_commits.size} commit that local does not have:", :magenta)
                                status.remote_commits.each do |line|
                                    lines << Autoproj.color("    #{line}", :magenta)
                                end
                            when Autobuild::Importer::Status::NEEDS_MERGE
                                result.local  = true
                                result.remote = true
                                lines << "  local and remote have diverged with respectively #{status.local_commits.size} and #{status.remote_commits.size} commits each"
                                lines << Autoproj.color("  -- local commits --", :blue)
                                status.local_commits.each do |line|
                                    lines << Autoproj.color("   #{line}", :blue)
                                end
                                lines << Autoproj.color("  -- remote commits --", :magenta)
                                status.remote_commits.each do |line|
                                    lines << Autoproj.color("   #{line}", :magenta)
                                end
                            end
                        end
                    end

                    if !sync_packages.empty?
                        Autoproj.message("#{sync_packages}: #{Autoproj.color("local and remote are in sync", :green)}")
                        sync_packages = ""
                    end

                    STDERR.print 

                    if lines.size == 1
                        Autoproj.message "#{pkg_name}: #{lines.first}"
                    else
                        Autoproj.message "#{pkg_name}:"
                        lines.each do |l|
                            Autoproj.message l
                        end
                    end
                end
                if !sync_packages.empty?
                    Autoproj.message("#{sync_packages}: #{Autoproj.color("local and remote are in sync", :green)}")
                    sync_packages = ""
                end
                return result
            end

        end
    end
end

