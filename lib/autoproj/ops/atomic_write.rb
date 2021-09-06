module Autoproj
    module Ops
        # Shamelessly stolen from ActiveSupport
        def self.atomic_write(file_name, temp_dir = Dir.tmpdir)
            require 'tempfile' unless defined?(Tempfile)
            require 'fileutils' unless defined?(FileUtils)

            temp_file = Tempfile.new(File.basename(file_name), temp_dir)
            yield temp_file
            temp_file.flush
            begin temp_file.fsync
            rescue NotImplementedError
            end
            temp_file.close

            begin
                # Get original file permissions
                old_stat = File.stat(file_name)
            rescue Errno::ENOENT
                # No old permissions, write a temp file to determine the defaults
                check_name = File.join(
                    File.dirname(file_name), ".permissions_check.#{Thread.current.object_id}.#{Process.pid}.#{rand(1000000)}")
                File.open(check_name, "w") {}
                old_stat = File.stat(check_name)
                File.unlink(check_name)
            end

            # Overwrite original file with temp file
            FileUtils.mv(temp_file.path, file_name)

            # Set correct permissions on new file
            File.chown(old_stat.uid, old_stat.gid, file_name)
            File.chmod(old_stat.mode, file_name)
        end
    end
end
