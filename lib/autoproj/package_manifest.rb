module Autoproj
    # Access to the information contained in a package's manifest.xml file
    #
    # Use PackageManifest.load to create
    class PackageManifest
        # Create a null manifest for the given package
        def self.null(package)
            new(package, null: true)
        end

        # Load a manifest.xml file and returns the corresponding PackageManifest
        # object
        #
        # @param [PackageDescription] the package we're loading it for
        # @param [String] file the path to the manifest.xml file
        # @param [Boolean] ros_manifest whether the file follows the ROS format
        # @return [PackageManifest]
        # @see parse
        def self.load(package, file, ros_manifest: false, condition_context: nil)
            loader_class = ros_manifest ? RosPackageManifest::Loader : Loader
            parse(package, File.read(file), path: file, loader_class: loader_class,
                                            condition_context: condition_context)
        end

        # Create a PackageManifest object from the XML content provided as a
        # string
        #
        # @param [PackageDescription] the package we're loading it for
        # @param [String] contents the manifest.xml contents as a string
        # @param [String] path the file path, used for error reporting
        # @param [Boolean] ros_manifest whether the file follows the ROS format
        # @return [PackageManifest]
        # @see load
        def self.parse(
            package, contents,
            path: "<loaded from string>", loader_class: Loader,
            condition_context: nil
        )
            manifest = loader_class::MANIFEST_CLASS.new(package, path)
            loader = loader_class.new(path, manifest,
                                      condition_context: condition_context)
            begin
                REXML::Document.parse_stream(contents, loader)
            rescue REXML::ParseException => e
                raise Autobuild::PackageException.new(package.name, "prepare"),
                      "invalid #{path}: #{e.message}"
            rescue Autoproj::ConfigError => e
                raise Autobuild::PackageException.new(package.name, "prepare"),
                      "invalid #{path}: #{e.message}"
            end
            manifest
        end

        ContactInfo = Struct.new :name, :email
        Dependency  = Struct.new :name, :optional, :modes

        # The Autobuild::Package instance this manifest applies on
        attr_accessor :package
        attr_reader :path
        attr_accessor :description
        attr_accessor :brief_description
        attr_reader :dependencies
        attr_accessor :tags
        attr_accessor :url
        attr_accessor :license
        attr_accessor :version
        attr_accessor :authors
        attr_accessor :maintainers
        attr_accessor :rock_maintainers

        # Add a declared dependency to this package
        def add_dependency(name, optional: false, modes: [])
            dependencies << Dependency.new(name, optional, modes)
        end

        def has_documentation?
            description
        end

        def documentation
            description || short_documentation
        end

        def has_short_documentation?
            brief_description
        end

        def short_documentation
            brief_description ||
                "no documentation available for package '#{package.name}' "\
                "in its manifest.xml file"
        end

        def initialize(package, path = nil, null: false)
            @package = package
            @path = path
            @dependencies = []
            @authors = []
            @maintainers = []
            @rock_maintainers = []
            @tags = []
            @null = null
        end

        # Whether this is a null manifest (used for packages that have actually
        # no manifest) or not
        def null?
            @null
        end

        def each_dependency(in_modes = [])
            return enum_for(__method__, in_modes) unless block_given?

            dependencies.each do |dep|
                if dep.modes.empty? || in_modes.any? { |m| dep.modes.include?(m) }
                    yield(dep.name, dep.optional)
                end
            end
        end

        def each_os_dependency(modes = Array.new, &block)
            Autoproj.warn_deprecated "#{self.class}##{__method__}",
                                     "call #each_dependency instead"
            each_dependency(modes, &block)
        end

        def each_package_dependency(modes = Array.new, &block)
            Autoproj.warn_deprecated "#{self.class}##{__method__}",
                                     "call #each_dependency instead"
            each_dependency(modes, &block)
        end

        def each_rock_maintainer
            return enum_for(__method__) unless block_given?

            rock_maintainers.each do |m|
                yield(m.name, m.email)
            end
        end

        def each_maintainer
            return enum_for(__method__) unless block_given?

            maintainers.each do |m|
                yield(m.name, m.email)
            end
        end

        # Enumerates the name and email of each author. If no email is present,
        # yields (name, nil)
        def each_author
            return enum_for(__method__) unless block_given?

            authors.each do |m|
                yield(m.name, m.email)
            end
        end

        # @api private
        #
        # REXML stream parser object used to filter nested tags
        class BaseLoader
            include REXML::StreamListener

            def initialize
                @tag_level = 0
            end

            def tag_start(name, attributes)
                toplevel_tag_start(name, attributes) if (@tag_level += 1) == 2
            end

            def tag_end(name)
                toplevel_tag_end(name) if (@tag_level -= 1) == 1
            end

            def text(text)
                @tag_text = @tag_text.dup
                @tag_text << text if @tag_text
            end
        end

        # @api private
        #
        # REXML stream parser object used to load the XML contents into a
        # {PackageManifest} object
        class Loader < BaseLoader
            attr_reader :path, :manifest

            MANIFEST_CLASS = PackageManifest

            def self.expand_configuration_variable(var, config)
                prefix = var[0, 1]
                var = var[1..-1] if prefix == "$"

                if var.start_with?("operating_system_name_")
                    os = config.get("operating_system", nil)
                    return "" if os.nil?

                    os_names, = os
                    return "" unless os_names.any? do |name|
                        var == "operating_system_name_#{name}"
                    end

                    return "true"
                end

                if var.start_with?("operating_system_version_")
                    os = config.get("operating_system", nil)
                    return "" if os.nil?

                    _, os_versions = os
                    return "" unless os_versions.any? do |ver|
                        var == "operating_system_version_#{ver.gsub(/[.,+-]/, '_')}"
                    end

                    return "true"
                end

                config.get(var).to_s
            end

            def initialize(path, manifest, condition_context: Configuration.new)
                super()
                @path = path
                @manifest = manifest
                @condition_parser = RosConditionParser.new do |var|
                    Loader.expand_configuration_variable(var, condition_context)
                end
            end

            def handle_condition(expr)
                return true unless expr && !expr.empty?

                @condition_parser.evaluate(expr)
            end

            def parse_depend_tag(tag_name, attributes, modes: [], optional: false)
                package = attributes["package"] || attributes["name"]
                unless package
                    raise InvalidPackageManifest,
                          "found '#{tag_name}' tag in #{path} "\
                          "without a 'package' attribute"
                end

                return unless handle_condition(attributes["condition"])

                if (tag_modes = attributes["modes"])
                    modes += tag_modes.split(",")
                end

                manifest.add_dependency(
                    package,
                    optional: optional || (attributes["optional"] == "1"),
                    modes: modes
                )
            end

            def parse_contact_field(text)
                text.strip.split(",").map do |str|
                    name, email = str.split("/").map(&:strip)
                    email = nil if email&.empty?
                    ContactInfo.new(name, email)
                end
            end

            TEXT_FIELDS = Set["url", "license", "version", "description"]
            AUTHOR_FIELDS = Set["author", "maintainer", "rock_maintainer"]

            def toplevel_tag_start(name, attributes)
                if name == "depend"
                    parse_depend_tag(name, attributes)
                elsif name == "depend_optional"
                    parse_depend_tag(name, attributes, optional: true)
                elsif name == "rosdep"
                    parse_depend_tag(name, attributes)
                elsif name =~ /^(\w+)_depend$/
                    parse_depend_tag(name, attributes, modes: [$1])
                elsif name == "description"
                    if (brief = attributes["brief"])
                        manifest.brief_description = brief
                    end
                    @tag_text = ""
                elsif TEXT_FIELDS.include?(name) || AUTHOR_FIELDS.include?(name)
                    @tag_text = ""
                elsif name == "tags"
                    @tag_text = ""
                else
                    @tag_text = nil
                end
            end

            def toplevel_tag_end(name)
                if AUTHOR_FIELDS.include?(name)
                    manifest.send("#{name}s").concat(parse_contact_field(@tag_text))
                elsif TEXT_FIELDS.include?(name)
                    field = @tag_text.strip
                    manifest.send("#{name}=", field) unless field.empty?
                elsif name == "tags"
                    manifest.tags.concat(@tag_text.strip.split(",").map(&:strip))
                end
                @tag_text = nil
            end
        end
    end
end
