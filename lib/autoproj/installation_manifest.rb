module Autoproj
    # Manifest of installed packages imported from another autoproj installation
    class InstallationManifest
        Package = Struct.new :name, :srcdir, :prefix

        attr_reader :path
        attr_reader :packages
        def initialize(path)
            @path = path
        end

        def load(path)
            @packages = CSV.read(path).map do |row|
                Package.new(*row)
            end
        end

        def each(&block)
            packages.each(&block)
        end

        def [](name)
            packages.find { |pkg| pkg.name == name }
        end

        def self.from_root(root_dir)
            manifest = InstallationManifest.new(root_dir)
            manifest_file = File.join(root_dir,  ".autoproj-installation-manifest")
            if !File.file?(manifest_file)
                raise ConfigError.new, "no .autoproj-installation-manifest file exists in #{root_dir}. You should probably rerun autoproj envsh in that folder first"
            end
            manifest.load(manifest_file)
            manifest
        end
    end
end
