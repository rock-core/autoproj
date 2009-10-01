require 'yaml'
require 'utilrb/kernel/options'
require 'nokogiri'
require 'set'

module Rubotics
    class VCSDefinition
        attr_reader :type
        attr_reader :url
        attr_reader :options

        def initialize(type, url, options)
            @type, @url, @options = type, url, options
            if type != "local" && !Autobuild.respond_to?(type)
                raise "version control #{type} is unknown to rubotics"
            end
        end

        def create_autobuild_importer
            Autobuild.send(type, url, options)
        end

        def to_s; "#{type}:#{url}" end
    end

    def self.vcs_definition_to_hash(spec)
        if spec.respond_to?(:to_str)
            vcs, *url = spec.to_str.split ':'
            spec = if url.empty?
                       source_dir = File.expand_path(File.join(Rubotics.config_dir, spec))
                       if !File.directory?(source_dir)
                           raise ConfigError, "'#{spec}' is neither a remote source specification, nor a local source definition"
                       end

                       Hash[:type => 'local', :url => source_dir]
                   else
                       Hash[:type => vcs.to_str, :url => url.join(":").to_str]
                   end
        end

        if spec[:url] && spec[:url] !~ /^(\w+:\/\/)?\//
            spec[:url] = File.expand_path(spec[:url], Rubotics.root_dir)
        end
        return spec
    end

    # Rubotics configuration files accept VCS definitions in three forms:
    #  * as a plain string, which is a relative/absolute path
    #  * as a plain string, which is a vcs_type:url string
    #  * as a hash
    #
    # This method normalizes the three forms into a VCSDefinition object
    def self.normalize_vcs_definition(spec)
        spec = vcs_definition_to_hash(spec)
        if !(spec[:type] && spec[:url])
            raise ConfigError, "the source specification #{spec} misses either the VCS type or an URL"
        end

        spec, vcs_options = Kernel.filter_options spec, :type => nil, :url => nil
        return VCSDefinition.new(spec[:type], spec[:url], vcs_options)
    end

    # A source is a version control repository which contains general source
    # information with package version control information (source.yml file),
    # package definitions (.autobuild files), and finally definition of
    # dependencies that are provided by the operating system (.osdeps file).
    class Source
        # The VCSDefinition object that defines the version control holding
        # information for this source. Local sources (i.e. the ones that are not
        # under version control) use the 'local' version control name. For them,
        # local? returns true.
        attr_accessor :vcs
        attr_reader :source_definition
        attr_reader :common_url_definitions

        # Create this source from a VCSDefinition object
        def initialize(vcs)
            @vcs = vcs
        end

        # True if this source has already been checked out on the local rubotics
        # installation
        def present?; File.directory?(local_dir) end
        # True if this source is local, i.e. is not under a version control
        def local?; vcs.type == "local" end
        # The directory in which data for this source will be checked out
        def local_dir
            if local?
                vcs.url
            else
                File.join(Rubotics.config_dir, "remotes", automatic_name)
            end
        end

        # A name generated from the VCS url
        def automatic_name
            vcs.url.gsub(/[^\w]/, '_')
        end

        # Returns the source name
        def name; @source_definition['name'] end

        # Load the source.yml file that describes this source
        def load_description_file
            if !present?
                raise "source #{vcs.type}:#{vcs.url} has not been fetched yet, cannot load description for it"
            end

            source_file = File.join(local_dir, "source.yml")
            if !File.exists?(source_file)
                raise "source #{vcs.type}:#{vcs.url} has been fetched, but does not have a source description file"
            end

            @source_definition = YAML.load(File.read(source_file))

            # Compute the definition of common URLs
            urls = source_definition['urls'] || Hash.new
            urls['HOME'] = ENV['HOME']

            redo_expansion = true
            @common_url_definitions = urls 
            while redo_expansion
                redo_expansion = false
                urls.dup.each do |name, url|
                    if contains_expansion?(url)
                        urls[name] = expand(url)
                        if urls[name] == url
                            raise "recursive definition of variable #{name} in source.yml"
                        end
                        redo_expansion = true
                    end
                end
            end
        end

        # True if the given string contains expansions
        def contains_expansion?(string); string =~ /\$/ end
        # Expands the given string as much as possible using the expansions
        # listed in the source.yml file, and returns it. Raises if not all
        # variables can be expanded.
        def expand(data, additional_expansions = Hash.new)
            if !source_definition
                load_description_file
            end

            if data.respond_to?(:to_hash)
                data.dup.each do |name, value|
                    data[name] = expand(value, additional_expansions)
                end
            else
                (additional_expansions.merge(common_url_definitions)).each do |name, expanded|
                    data = data.gsub /\$#{name}\b/, expanded
                end
                if contains_expansion?(data)
                    raise "some variables cannot be expanded, the result is #{data.inspect}"
                end
            end

            data
        end

        # Returns an importer definition for the given package, if one is
        # available. Otherwise returns nil.
        #
        # The returned value is a VCSDefinition object.
        def importer_definition_for(package_name)
            urls = source_definition['urls'] || Hash.new
            urls['HOME'] = ENV['HOME']

            vcs         = source_definition['version_control']
            default_vcs = source_definition['default_version_control']
            vcs_spec = if vcs && vcs[package_name]
                           vcs[package_name]
                       elsif default_vcs
                           default_vcs
                       end

            if vcs_spec
                expansions = Hash["PACKAGE" => package_name]
                if default_vcs
                    expansions["DEFAULT"] = expand(default_vcs, expansions)
                end

                vcs_spec = expand(vcs_spec, expansions)
                vcs_spec = Rubotics.vcs_definition_to_hash(vcs_spec)
                if default_vcs
                    default_vcs = expand(default_vcs, expansions)
                    default_vcs_spec = Rubotics.vcs_definition_to_hash(default_vcs)
                    vcs_spec = default_vcs_spec.merge(vcs_spec)
                end

                vcs_spec.dup.each do |name, value|
                    vcs_spec[name] = expand(value, expansions)
                end

                begin
                    Rubotics.normalize_vcs_definition(vcs_spec)
                rescue Exception => e
                    raise e.class, "cannot load package #{package_name}: #{e.message}"
                end
            end
        end
    end

    class Manifest
        FakePackage = Struct.new :name, :srcdir
	def self.load(file)
	    Manifest.new(YAML.load(File.read(file)))
	end

        # The manifest data as a Hash
        attr_reader :data

        # The set of packages defined so far as a mapping from package name to 
        # [Autobuild::Package, source, file] tuple
        attr_reader :packages

        # A mapping from package names into PackageManifest objects
        attr_reader :package_manifests

	def initialize(data)
	    @data = data
            @packages = Hash.new
            @package_manifests = Hash.new
	end

        # Lists the autobuild files that are part of the sources listed in this
        # manifest
	def each_autobuild_file
            if !block_given?
                return enum_for(:each_source_file)
            end

            each_source do |source|
		Dir.glob(File.join(source.local_dir, "*.autobuild")).each do |file|
		    yield(source, file)
		end
            end
	end

        def each_osdeps_file
            if !block_given?
                return enum_for(:each_source_file)
            end

            each_source do |source|
		Dir.glob(File.join(source.local_dir, "*.osdeps")).each do |file|
		    yield(source, file)
		end
            end
        end

        # Like #each_source, but filters out local sources
        def each_remote_source
            if !block_given?
                enum_for(:each_remote_source)
            else
                each_source do |source|
                    if !source.local?
                        yield(source)
                    end
                end
            end
        end

        # call-seq:
        #   each_source { |source_description| ... }
        #
        # Lists all sources defined in this manifest, by yielding a Source
        # object that describes the source.
        def each_source
            if !block_given?
                return enum_for(:each_source)
            end

	    data['sources'].each do |spec|
                # Look up for short notation (i.e. not an explicit hash). It is
                # either vcs_type:url or just url. In the latter case, we expect
                # 'url' to be a path to a local directory
                vcs_def = begin
                              Rubotics.normalize_vcs_definition(spec)
                          rescue Exception => e
                              raise "cannot load source #{spec}: #{e.message}"
                          end

                source = Source.new(vcs_def)
                if source.present?
                    source.load_description_file
                end

                yield(source)
            end
        end

        # Register a new package
        def register_package(package, source, file)
            @packages[package.name] = [package, source, file]
        end

        def definition_source(package_name)
            @packages[package_name][1]
        end
        def definition_file(package_name)
            @packages[package_name][2]
        end

        # Lists all defined packages and where they have been defined
        def each_package
            if !block_given?
                return enum_for(:each_package)
            end
            packages.each_value { |package, _| yield(package) }
        end

        def update_remote_sources
            each_remote_source do |source|
                importer     = source.vcs.create_autobuild_importer
                fake_package = FakePackage.new(source.automatic_name, source.local_dir)

                importer.import(fake_package)
            end
        end

        # Sets up the package importers based on the information listed in
        # the source's source.yml 
        #
        # The priority logic is that we take the sources one by one in the order
        # listed in the rubotics main manifest, and first come first used.
        #
        # A source that defines a particular package in its autobuild file
        # *must* provide the corresponding VCS line in its source.yml file.
        # However, it is possible for a source that does *not* define a package
        # to override the VCS
        #
        # In other words: if package P is defined by source S1, and source S0
        # imports S1, then
        #  * S1 must have a VCS line for P
        #  * S0 can have a VCS line for P, which would override the one defined
        #    by S1
        def load_importers
            packages.each_value do |package, package_source, package_source_file|
                vcs = each_source.find do |source|
                    vcs = source.importer_definition_for(package.name)
                    if vcs
                        break(vcs)
                    elsif package_source.name == source.name
                        break
                    end
                end

                if vcs
                    package.importer = vcs.create_autobuild_importer
                else
                    raise "#{package_source.name} defines #{package.name}, but does not provide a version control definition for it"
                end
            end
        end

        # Loads the package's manifest.xml files, and extracts dependency
        # information from them. The dependency information is then used applied
        # to the autobuild packages.
        #
        # Right now, the absence of a manifest makes rubotics only issue a
        # warning. This will later be changed into an error.
        def load_package_manifests
            packages.each_value do |package, source, file|
                manifest_path = File.join(package.srcdir, "manifest.xml")
                if !File.file?(manifest_path)
                    Rubotics.warn "#{package.name} from #{source.name} does not have a manifest"
                    next
                end

                manifest = PackageManifest.load(manifest_path)
                package_manifests[package.name] = manifest

                manifest.each_package_dependency do |name|
                    if Rubotics.verbose
                        STDERR.puts "  #{package.name} depends on #{name}"
                    end
                    package.depends_on name
                end
            end
        end

        def install_os_dependencies
            # Generate the list of OS dependencies, load the osdeps files, and
            # call OSDependencies#install
            osdeps = OSDependencies.new
            each_osdeps_file do |source, file|
                osdeps.merge(OSDependencies.load(file))
            end

            all_packages = Set.new
            package_manifests.each_value do |pkg_manifest|
                all_packages |= pkg_manifest.each_os_dependency.to_set
            end

            osdeps.install(all_packages)
        end
    end

    # The singleton manifest object on which the current run works
    class << self
        attr_accessor :manifest
    end

    class PackageManifest
        def self.load(file)
            doc = Nokogiri::XML(File.read(file))
            PackageManifest.new(doc)
        end

        attr_reader :xml
        def initialize(doc)
            @xml = doc
        end

        def each_os_dependency
            if block_given?
                xml.xpath('//rosdep').each do |node|
                    yield(node['name'])
                end
            else
                enum_for :each_os_dependency
            end
        end

        def each_package_dependency
            if block_given?
                xml.xpath('//depend').each do |node|
                    yield(node['package'])
                end
            else
                enum_for :each_package_dependency
            end
        end
    end
end

