require 'stringio'

module Autoproj
    module Ops
        # Shamelessly stolen from ActiveSupport
        def self.atomic_write(file_name, temp_dir = Dir.tmpdir)
            require 'tempfile' unless defined?(Tempfile)
            require 'fileutils' unless defined?(FileUtils)

            begin
                # Get original file permissions
                old_stat = File.stat(file_name)
                exist = true
            rescue Errno::ENOENT
                # No old permissions, write a temp file to determine the defaults
                check_name = File.join(
                    File.dirname(file_name),
                    ".permissions_check.#{Thread.current.object_id}."\
                    "#{Process.pid}.#{rand(1_000_000)}"
                )
                File.open(check_name, "w") {}
                old_stat = File.stat(check_name)
                File.unlink(check_name)
                exist = false
            end

            out = StringIO.new
            yield out

            if exist && out.size == old_stat.size
                return if out.string == File.read(file_name)
            end

            temp_file = Tempfile.new(File.basename(file_name), temp_dir)
            temp_file.write out.string
            temp_file.flush
            begin temp_file.fsync
            rescue NotImplementedError # rubocop:disable Lint/HandleExceptions
            end
            temp_file.close

            # Overwrite original file with temp file
            FileUtils.mv(temp_file.path, file_name)

            # Set correct permissions on new file
            File.chown(old_stat.uid, old_stat.gid, file_name)
            File.chmod(old_stat.mode, file_name)
        end
    end
end
