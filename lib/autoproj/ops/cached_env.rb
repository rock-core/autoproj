require "autobuild/environment"

module Autoproj
    module Ops
        def self.cached_env_path(root_dir)
            File.join(root_dir, ".autoproj", "env.yml")
        end

        def self.load_cached_env(root_dir)
            path = cached_env_path(root_dir)
            if File.file?(path)
                env = YAML.safe_load(File.read(path))
                Autobuild::Environment::ExportedEnvironment.new(
                    env["set"], env["unset"], env["update"]
                )
            end
        end

        def self.save_cached_env(root_dir, env)
            env = env.exported_environment
            path = cached_env_path(root_dir)
            existing =
                begin
                    YAML.safe_load(File.read(path))
                rescue Exception
                end

            env = Hash["set" => env.set, "unset" => env.unset, "update" => env.update]
            if env != existing
                Ops.atomic_write(path) do |io|
                    io.write YAML.dump(env)
                end
                true
            end
        end
    end
end
