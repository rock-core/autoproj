module Autoproj
    # Manifest of installed packages imported from another autoproj installation
    class InstallationManifest
        Package = Struct.new :name, :type, :vcs, :srcdir, :importdir,
                             :prefix, :builddir, :logdir, :dependencies do
            def self.from_package_definition(pkg)
                v = pkg.autobuild
                new(v.name, v.class.name, pkg.vcs.to_hash,
                    v.srcdir,
                    (v.importdir if v.respond_to?(:importdir)),
                    v.prefix, 
                    (v.builddir if v.respond_to?(:builddir)),
                    v.logdir, v.dependencies)
            end
        end

        PackageSet = Struct.new :name, :vcs, :raw_local_dir, :user_local_dir do
            def self.from_package_set(pkg_set)
                new(pkg_set.name, pkg_set.vcs.to_hash, pkg_set.raw_local_dir, pkg_set.user_local_dir)
            end
        end

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
                            entry['package_set'], entry['vcs'], entry['raw_local_dir'], entry['user_local_dir'])
                        package_sets[pkg_set.name] = pkg_set
                    elsif entry['type'] == 'PackageSet'
                        pkg_set = PackageSet.new(
                            entry['name'], entry['vcs'], entry['raw_local_dir'], entry['user_local_dir'])
                        package_sets[pkg_set.name] = pkg_set
                    else
                        pkg = Package.new(
                            entry['name'], entry['type'], entry['vcs'], entry['srcdir'], entry['importdir'],
                            entry['prefix'], entry['builddir'], entry['logdir'], entry['dependencies'])
                        packages[pkg.name] = pkg
                    end
                end
            end
        end

        # Save the installation manifest
        def save(path = self.path)
            Ops.atomic_write(path) do |io|
                marshalled_package_sets = each_package_set.map do |pkg_set|
                    h = PackageSet.from_package_set(pkg_set).to_h.transform_keys(&:to_s)
                    h['type'] = 'PackageSet'
                    h
                end
                marshalled_packages = each_package.map do |package_def|
                    Package.from_package_definition(package_def).to_h.transform_keys(&:to_s)
                end
                io.write YAML.dump(marshalled_package_sets + marshalled_packages)
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

