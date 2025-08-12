module Autoproj
    # Manifest of installed packages imported from another autoproj installation
    class InstallationManifest
        Package = Struct.new :name, :type, :vcs, :srcdir, :importdir,
                             :prefix, :builddir, :logdir, :dependencies, :manifest
        PackageSet = Struct.new :name, :vcs, :raw_local_dir, :user_local_dir

        Manifest = Struct.new(
            :description, :brief_description, :url, :license, :version,
            :authors, :maintainers, :rock_maintainers, :dependencies, :tags,
            keyword_init: true
        )

        # Copied from PackageManifest, must keep the same interface
        ContactInfo = Struct.new :name, :email, keyword_init: true

        # Copied from PackageManifest, must keep the same interface
        Dependency  = Struct.new :name, :optional, :modes, keyword_init: true

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
                    manifest = convert_manifest(v.description)
                    Package.new(
                        v.name, v.class.name, pkg.vcs.to_hash, v.srcdir,
                        (v.importdir if v.respond_to?(:importdir)),
                        v.prefix,
                        (v.builddir if v.respond_to?(:builddir)),
                        v.logdir, v.dependencies,
                        manifest
                    )
                else
                    pkg
                end
        end

        def convert_manifest(manifest)
            fields = Manifest.members.each_with_object({}) do |k, h|
                h[k] = manifest.send(k)
            end
            Manifest.new(**fields)
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
                            entry["package_set"], entry["vcs"], entry["raw_local_dir"], entry["user_local_dir"]
                        )
                        package_sets[pkg_set.name] = pkg_set
                    else
                        manifest = load_manifest(entry["manifest"])
                        pkg = Package.new(
                            entry["name"], entry["type"], entry["vcs"], entry["srcdir"], entry["importdir"],
                            entry["prefix"], entry["builddir"], entry["logdir"], entry["dependencies"],
                            manifest
                        )
                        packages[pkg.name] = pkg
                    end
                end
            end
        end

        def load_manifest(entry)
            entry = entry.dup
            %w[authors maintainers rock_maintainers].each do |field|
                entry[field] = load_contact_list(entry[field])
            end
            entry["dependencies"] = load_manifest_dependencies(entry["dependencies"])

            Manifest.new(**entry.transform_keys(&:to_sym))
        end

        def load_contact_list(list)
            list.map { |fields| ContactInfo.new(**fields.transform_keys(&:to_sym)) }
        end

        def load_manifest_dependencies(list)
            list.map { |fields| Dependency.new(**fields.transform_keys(&:to_sym)) }
        end

        # Save the installation manifest
        def save(path = @path)
            Ops.atomic_write(path) do |io|
                marshalled_package_sets = each_package_set.map do |pkg_set|
                    set = struct_to_yaml(pkg_set)
                    set["package_set"] = set["name"]
                    set
                end
                marshalled_packages = each_package.map do |pkg|
                    struct_to_yaml(pkg)
                end
                io.write YAML.dump(marshalled_package_sets + marshalled_packages)
            end
        end

        def object_to_yaml(obj)
            case obj
            when Struct
                struct_to_yaml(obj)
            when Array
                obj.map { |el| object_to_yaml(el) }
            when Hash
                hash_to_yaml(obj)
            else
                obj
            end
        end

        def struct_to_yaml(obj)
            obj.to_h
               .transform_keys(&:to_s)
               .transform_values { |el| object_to_yaml(el) }
        end

        def hash_to_yaml(obj)
            obj.transform_values { |el| object_to_yaml(el) }
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
            unless manifest.exist?
                raise ConfigError.new,
                      "no #{path} file found. You should probably rerun " \
                      "autoproj envsh in that folder first"
            end

            manifest.load
            manifest
        end
    end
end
