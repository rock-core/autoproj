module Autoproj
    # Manifest of installed packages imported from another autoproj installation
    class InstallationManifest
        Package = Struct.new :name, :srcdir, :prefix, :builddir

        DEFAULT_MANIFEST_NAME = ".autoproj-installation-manifest"

        attr_reader :path
        attr_reader :packages
        def initialize(path)
            @path = path
        end

        def default_manifest_path
            File.join(path, DEFAULT_MANIFEST_NAME)
        end
            
        def load(path = default_manifest_path)
            @packages = CSV.read(path).map do |row|
                pkg = Package.new(*row)
                if pkg.builddir && pkg.builddir.empty?
                    pkg.builddir = nil
                end
                pkg
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
