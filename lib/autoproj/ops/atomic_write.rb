# frozen_string_literal: true

require "tempfile"
require "fileutils"

module Autoproj
    module Ops
        # Write to a file atomically. Useful for situations where you don't
        # want other processes or threads to see half-written files.
        #
        #   File.atomic_write('important.file') do |file|
        #     file.write('hello')
        #   end
        #
        # This method needs to create a temporary file. By default it will create it
        # in the same directory as the destination file. If you don't like this
        # behavior you can provide a different directory but it must be on the
        # same physical filesystem as the file you're trying to write.
        #
        #   File.atomic_write('/data/something.important', '/data/tmp') do |file|
        #     file.write('hello')
        #   end
        #
        # Shamelessly stolen from ActiveSupport
        def self.atomic_write(file_name, temp_dir = File.dirname(file_name))
            Tempfile.open(".#{File.basename(file_name)}", temp_dir) do |temp_file|
                temp_file.binmode
                yield temp_file
                temp_file.close

                old_stat = begin
                    # Get original file permissions
                    File.stat(file_name)
                rescue Errno::ENOENT
                    # If not possible, probe which are the default permissions in the
                    # destination directory.
                    probe_stat_in(File.dirname(file_name))
                end

                if old_stat
                    # Set correct permissions on new file
                    begin
                        File.chown(old_stat.uid, old_stat.gid, temp_file.path)
                        # This operation will affect filesystem ACL's
                        File.chmod(old_stat.mode, temp_file.path)
                    rescue Errno::EPERM, Errno::EACCES
                        # Changing file ownership failed, moving on.
                    end
                end

                # Overwrite original file with temp file
                File.rename(temp_file.path, file_name)
            end
        end

        # Private utility method.
        def self.probe_stat_in(dir) # :nodoc:
            basename = [
                ".permissions_check",
                Thread.current.object_id,
                Process.pid,
                rand(1000000)
            ].join(".")

            file_name = File.join(dir, basename)
            FileUtils.touch(file_name)
            File.stat(file_name)
        rescue Errno::ENOENT
            file_name = nil
        ensure
            FileUtils.rm_f(file_name) if file_name
        end
    end
end
