module Autoproj
    # Manifest of installed packages imported from another autoproj installation
    class InstallationManifest
        Package = Struct.new :name, :srcdir, :prefix, :builddir, :dependencies

        attr_reader :path
        attr_reader :packages
        def initialize(path)
            @path = path
            @packages = Hash.new
        end

        def exist?
            File.exist?(path)
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
            
        def load
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

        # Save the installation manifest
        def save(path = self.path)
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

        # Enumerate the packages from this manifest
        #
        # @yieldparam [Package]
        def each(&block)
            packages.each_value(&block)
        end

        # Returns information about a given package
        #
        # @return [Package]
        def [](name)
            packages[name]
        end

        # Returns the default Autoproj installation manifest path for a given
        # autoproj workspace root
        #
        # @param [String] root_dir
        # @return [String]
        def self.path_for_root(root_dir)
            File.join(root_dir, '.autoproj', 'installation-manifest')
        end

        def self.from_root(root_dir)
            path = path_for_root(root_dir)
            manifest = InstallationManifest.new(path)
            if !manifest.exist?
                raise ConfigError.new, "no #{path} file found. You should probably rerun autoproj envsh in that folder first"
            end
            manifest.load
            manifest
        end
    end
end

