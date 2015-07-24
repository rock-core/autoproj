module Autoproj
    # Manifest of installed packages imported from another autoproj installation
    class InstallationManifest
        Package = Struct.new :name, :srcdir, :prefix, :builddir, :dependencies

        DEFAULT_MANIFEST_NAME = ".autoproj-installation-manifest"

        attr_reader :path
        attr_reader :packages
        def initialize(path)
            @path = path
            @packages = Hash.new
        end

        def default_manifest_path
            File.join(path, DEFAULT_MANIFEST_NAME)
        end

        def exist?
            File.exist?(default_manifest_path)
        end

        def [](name)
            packages[name]
        end

        def []=(name, pkg)
            packages[name] = pkg
        end

        def delete_if
            packages.delete_if { |_, pkg| yield(pkg) }
        end
            
        def load(path = default_manifest_path)
            @packages = Hash.new
            raw = YAML.load(File.open(path))
            if raw.respond_to?(:to_str) # old CSV-based format
                CSV.read(path).map do |row|
                    name, srcdir, prefix, builddir = *row
                    builddir = nil if builddir && builddir.empty?
                    packages[name] = Package.new(name, srcdir, prefix, builddir, [])
                end
                save(path)
            else
                raw.each do |entry|
                    pkg = Package.new(
                        entry['name'], entry['srcdir'], entry['prefix'],
                        entry['builddir'], entry['dependencies'])
                    packages[pkg.name] = pkg
                end
            end
        end

        def save(path = default_manifest_path)
            File.open(path, 'w') do |io|
                marshalled_packages = packages.values.map do |v|
                    Hash['name' => v.name,
                         'srcdir' => v.srcdir,
                         'builddir' => (v.builddir if v.respond_to?(:builddir)),
                         'prefix' => v.prefix,
                         'dependencies' => v.dependencies]
                end
                YAML.dump(marshalled_packages, io)
            end
        end

        def each(&block)
            packages.each(&block)
        end

        def [](name)
            packages.each_value.find { |pkg| pkg.name == name }
        end

        def self.from_root(root_dir)
            manifest = InstallationManifest.new(root_dir)
            if !manifest.exist?
                raise ConfigError.new, "no #{DEFAULT_MANIFEST_NAME} file exists in #{root_dir}. You should probably rerun autoproj envsh in that folder first"
            end
            manifest.load
            manifest
        end
    end
end

