module Rubotics
    BASE_DIR     = File.expand_path(File.join('..', '..'), File.dirname(__FILE__))

    class UserError < RuntimeError; end

    def self.root_dir
        dir = Dir.pwd
        while dir != "/" && !File.directory?(File.join(dir, "rubotics"))
            dir = File.dirname(dir)
        end
        if dir == "/"
            raise UserError, "not in a Rubotics installation"
        end
        dir
    end

    def self.config_dir
        File.join(root_dir, "rubotics")
    end
    def self.build_dir
	File.join(root_dir, "build")
    end

    def self.config_file(file)
        File.join(config_dir, file)
    end

    def self.run_as_user(*args)
        if !system(*args)
            raise "failed to run #{args.join(" ")}"
        end
    end

    def self.run_as_root(*args)
        if !system('sudo', *args)
            raise "failed to run #{args.join(" ")} as root"
        end
    end
end

