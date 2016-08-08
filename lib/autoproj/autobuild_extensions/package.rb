module Autoproj
    module AutobuildExtensions
        module Package
            # Tags explicitely added with #add_tag
            attr_reader :added_tags

            attr_reader :optional_dependencies

            attr_reader :os_packages

            attr_writer :ws
            def ws
                @ws ||= Autoproj.workspace
            end

            # The Autoproj::PackageManifest object that describes this package
            attr_accessor :description

            def initialize(spec = Hash.new)
                super
                @ws = nil
                @os_packages = Set.new
                @added_tags = Set.new
                @optional_dependencies = Set.new
                @description = PackageManifest.new(self)
            end

            # The set of tags for this package. This is an union of the tags
            # contained in +description+ and the ones explicitely added with
            # #add_tag
            def tags
                result = @added_tags.dup
                if description
                    result |= description.tags.to_set
                end
                result
            end

            # Add a tag to the package. Use this if you don't want the tag to be
            # shared with everyone that uses the package (i.e. cannot go in
            # manifest.xml)
            def add_tag(tag)
                @added_tags << tag
            end

            # True if this package is tagged with the given tag string
            def has_tag?(tag)
                tags.include?(tag.to_s)
            end

            # Asks autoproj to remove references to the given obsolete oroGen
            # package
            def remove_obsolete_installed_orogen_package(name)
                post_install do
                    path = File.join(prefix, 'lib', 'pkgconfig')
                    Dir.glob(File.join(path, "#{name}-*.pc")) do |pcfile|
                        Autoproj.message "  removing obsolete file #{pcfile}", :bold
                        FileUtils.rm_f pcfile
                    end
                    pcfile = File.join(path, "orogen-project-#{name}.pc")
                    if File.exist?(pcfile)
                        Autoproj.message "  removing obsolete file #{pcfile}", :bold
                        FileUtils.rm_f pcfile
                    end
                end
            end

            # Asks autoproj to remove the given file in the package's installation
            # prefix
            def remove_obsolete_installed_file(*path)
                post_install do
                    path = File.join(prefix, *path)
                    if File.exist?(path)
                        Autoproj.message "  removing obsolete file #{path}", :bold
                        FileUtils.rm_f path
                    end
                end
            end

            # Ask autoproj to run the given block after this package has been
            # imported
            def post_import(&block)
                Autoproj.post_import(self, &block)
            end

            def autoproj_name # :nodoc:
                srcdir.gsub(/^#{Regexp.quote(ws.root_dir)}\//, '')
            end

            def depends_on(name)
                if name.respond_to?(:name) # probably a Package object
                    name = name.name
                end

                pkg_autobuild, pkg_os = partition_package(name)
                pkg_autobuild.each do |pkg|
                    super(pkg)
                end
                @os_packages.merge(pkg_os.to_set)
            end

            def all_dependencies_with_osdeps(set = Set.new)
                original_set = set.dup
                all_dependencies(set)
                set.dup.each do |dep_pkg_name|
                    next if original_set.include?(dep_pkg_name)
                    if dep_pkg = ws.manifest.find_autobuild_package(dep_pkg_name)
                        set.merge(dep_pkg.os_packages)
                    else
                        raise ArgumentError, "#{dep_pkg_name}, which is listed as a dependency of #{name}, is not the name of a known package"
                    end
                end
                set.merge(os_packages)
                set
            end

            def depends_on_os_package(name)
                depends_on(name)
            end

            def remove_dependency(name)
                dependencies.delete name
                optional_dependencies.delete name
                os_packages.delete name
            end

            def optional_dependency(name)
                optional_dependencies << name
            end

            def partition_package(pkg_name)
                pkg_autobuild, pkg_osdeps = [], []
                ws.manifest.resolve_package_name(pkg_name).each do |type, dep_name|
                    if type == :osdeps
                        pkg_osdeps << dep_name
                    elsif type == :package
                        pkg_autobuild << dep_name
                    else raise Autoproj::InternalError, "expected package type to be either :osdeps or :package, got #{type.inspect}"
                    end
                end
                return pkg_autobuild, pkg_osdeps
            end

            def partition_optional_dependencies
                packages, osdeps = [], []
                optional_dependencies.each do |name|
                    begin
                        pkg_autobuild, pkg_osdeps = partition_package(name)
                        packages.concat(pkg_autobuild)
                        osdeps.concat(pkg_osdeps)
                    rescue Autoproj::PackageNotFound
                        # Simply ignore non-existent optional dependencies
                    end
                end
                return packages, osdeps
            end
        end
    end
end
