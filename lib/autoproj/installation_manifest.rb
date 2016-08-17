module Autoproj
    # Manifest of installed packages imported from another autoproj installation
    class InstallationManifest
        Package = Struct.new :name, :srcdir, :prefix, :builddir, :dependencies
        PackageSet = Struct.new :name, :raw_local_dir, :user_local_dir

        attr_reader :path
        attr_reader :packages
        attr_reader :package_sets
        def initialize(path)
            @path = path
            @packages = Hash.new
            @package_sets = Hash.new
        end

        def exist?
            File.exist?(path)
        end

        def add_package(pkg)
            packages[pkg.name] = pkg
        end

        def add_package_set(pkg_set)
            package_sets[pkg_set.name] = pkg_set
        end

        def each_package_set(&block)
            package_sets.each_value(&block)
        end
            
        def each_package(&block)
            packages.each_value(&block)
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
                    if entry['package_set']
                        pkg_set = PackageSet.new(
                            entry['package_set'], entry['raw_local_dir'], entry['user_local_dir'])
                        package_sets[pkg_set.name] = pkg_set
                    else
                        pkg = Package.new(
                            entry['name'], entry['srcdir'], entry['prefix'],
                            entry['builddir'], entry['dependencies'])
                        packages[pkg.name] = pkg
                    end
                end
            end
        end

        # Save the installation manifest
        def save(path = self.path)
            File.open(path, 'w') do |io|
                marshalled_package_sets = each_package_set.map do |v|
                    Hash['package_set' => v.name,
                         'raw_local_dir' => v.raw_local_dir,
                         'user_local_dir' => v.user_local_dir]
                end
                marshalled_packages = each_package.map do |v|
                    v = v.autobuild
                    Hash['name' => v.name,
                         'srcdir' => v.srcdir,
                         'builddir' => (v.builddir if v.respond_to?(:builddir)),
                         'prefix' => v.prefix,
                         'dependencies' => v.dependencies]
                end
                YAML.dump(marshalled_package_sets + marshalled_packages, io)
            end
        end

        # Returns the default Autoproj installation manifest path for a given
        # autoproj workspace root
        #
        # @param [String] root_dir
        # @return [String]
        def self.path_for_workspace_root(root_dir)
            File.join(root_dir, '.autoproj', 'installation-manifest')
        end

        def self.from_workspace_root(root_dir)
            path = path_for_workspace_root(root_dir)
            manifest = InstallationManifest.new(path)
            if !manifest.exist?
                raise ConfigError.new, "no #{path} file found. You should probably rerun autoproj envsh in that folder first"
            end
            manifest.load
            manifest
        end
    end
end

