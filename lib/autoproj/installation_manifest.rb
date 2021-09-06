module Autoproj
    # Manifest of installed packages imported from another autoproj installation
    class InstallationManifest
        Package = Struct.new :name, :type, :vcs, :srcdir, :importdir,
                             :prefix, :builddir, :logdir, :dependencies
        PackageSet = Struct.new :name, :vcs, :raw_local_dir, :user_local_dir

        attr_reader :path
        attr_reader :packages
        attr_reader :package_sets

        def initialize(path = nil)
            @path = path
            @packages = Hash.new
            @package_sets = Hash.new
        end

        def exist?
            File.exist?(path) if path
        end

        # Add a {PackageDefinition} to this manifest
        #
        # @return [Package] the package in the installation manifest format
        def add_package(pkg)
            packages[pkg.name] =
                case pkg
                when PackageDefinition
                    v = pkg.autobuild
                    Package.new(
                        v.name, v.class.name, pkg.vcs.to_hash, v.srcdir,
                        (v.importdir if v.respond_to?(:importdir)),
                        v.prefix,
                        (v.builddir if v.respond_to?(:builddir)),
                        v.logdir, v.dependencies
                    )
                else
                    pkg
                end
        end

        # Add a {Autoproj::PackageSet} to this manifest
        #
        # @return [PackageSet] the package set in the installation manifest format
        def add_package_set(pkg_set)
            package_sets[pkg_set.name] = PackageSet.new(
                pkg_set.name, pkg_set.vcs.to_hash,
                pkg_set.raw_local_dir, pkg_set.user_local_dir
            )
        end

        # Enumerate this {InstallationManifest}'s package sets
        #
        # @yieldparam [PackageSet]
        def each_package_set(&block)
            package_sets.each_value(&block)
        end

        # Enumerate this {InstallationManifest}'s packages
        #
        # @yieldparam [Package]
        def each_package(&block)
            packages.each_value(&block)
        end

        # Resolve a package set by name
        #
        # @return [Package]
        def find_package_set_by_name(name)
            @package_sets[name]
        end

        # Resolve a package by name
        #
        # @return [Package]
        def find_package_by_name(name)
            @packages[name]
        end

        def load(path = @path)
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
                    if entry["package_set"]
                        pkg_set = PackageSet.new(
                            entry["package_set"], entry["vcs"], entry["raw_local_dir"], entry["user_local_dir"])
                        package_sets[pkg_set.name] = pkg_set
                    else
                        pkg = Package.new(
                            entry["name"], entry["type"], entry["vcs"], entry["srcdir"], entry["importdir"],
                            entry["prefix"], entry["builddir"], entry["logdir"], entry["dependencies"])
                        packages[pkg.name] = pkg
                    end
                end
            end
        end

        # Save the installation manifest
        def save(path = @path)
            Ops.atomic_write(path) do |io|
                marshalled_package_sets = each_package_set.map do |pkg_set|
                    set = pkg_set.to_h.transform_keys(&:to_s)
                    set["package_set"] = set["name"]
                    set
                end
                marshalled_packages = each_package.map do |pkg|
                    pkg.to_h.transform_keys(&:to_s)
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
            File.join(root_dir, ".autoproj", "installation-manifest")
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
