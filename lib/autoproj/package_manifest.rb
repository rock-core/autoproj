module Autoproj
    # Access to the information contained in a package's manifest.xml file
    #
    # Use PackageManifest.load to create
    class PackageManifest
        # Load a manifest.xml file and returns the corresponding
        # PackageManifest object
        def self.load(package, file)
            doc =
                begin REXML::Document.new(File.read(file))
                rescue REXML::ParseException => e
                    raise Autobuild::PackageException.new(package.name, 'prepare'), "invalid #{file}: #{e.message}"
                end

            PackageManifest.new(package, doc)
        end

        # The Autobuild::Package instance this manifest applies on
        attr_reader :package
        # The raw XML data as a Nokogiri document
        attr_reader :xml

        # The list of tags defined for this package
        #
        # Tags are defined as multiple <tags></tags> blocks, each of which can
        # contain multiple comma-separated tags 
        def tags
            result = []
            xml.elements.each('package/tags') do |node|
                result.concat((node.text || "").strip.split(','))
            end
            result
        end

        def has_documentation?
            xml.elements.each('package/description') do |node|
                doc = (node.text || "").strip
                if !doc.empty?
                    return true
                end
            end
            return false
        end

        def documentation
            xml.elements.each('package/description') do |node|
                doc = (node.text || "").strip
                if !doc.empty?
                    return doc
                end
            end
            return short_documentation
        end

        def has_short_documentation?
            xml.elements.each('package/description') do |node|
                doc = node.attributes['brief']
                if doc
                    doc = doc.to_s.strip
                end
                if doc && !doc.empty?
                    return true
                end
            end
            false
        end

        def short_documentation
            xml.elements.each('package/description') do |node|
                doc = node.attributes['brief']
                if doc
                    doc = doc.to_s.strip
                end
                if doc && !doc.empty?
                    return doc.to_s
                end
            end
            "no documentation available for #{package.name} in its manifest.xml file"
        end

        def initialize(package, doc = REXML::Document.new)
            @package = package
            @xml = doc
        end

        # Whether this is a null manifest (used for packages that have actually
        # no manifest) or not
        def null?
            !xml.elements['/package']
        end

        def each_dependency(in_modes = Array.new, &block)
            return enum_for(__method__) if !block_given?

            depend_nodes = xml.elements.to_a('package/depend') +
                xml.elements.to_a('package/depend_optional') +
                xml.elements.to_a('package/rosdep')
            in_modes.each do |m|
                depend_nodes += xml.elements.to_a("package/#{m}_depend")
            end

            depend_nodes.each do |node|
                dependency = node.attributes['package'] || node.attributes['name']
                optional   = (node.attributes['optional'].to_s == '1' || node.name == "depend_optional")
                modes      = node.attributes['modes'].to_s.split(',')
                if node.name =~ /^(\w+)_depend$/
                    modes << $1
                end
                if !modes.empty? && modes.none? { |m| in_modes.include?(m) }
                    next
                end

                if dependency
                    yield(dependency, optional)
                elsif node.name == 'rosdep'
                    raise ConfigError.new, "manifest of #{package.name} has a <rosdep> tag without a 'name' attribute"
                else
                    raise ConfigError.new, "manifest of #{package.name} has a <#{node.name}> tag without a 'package' attribute"
                end
            end

            package.os_packages.each do |name|
                yield(name, false)
            end
        end

        def each_os_dependency(modes = Array.new, &block)
            Autoproj.warn "PackageManifest#each_os_dependency called, fix your code"
            return each_dependency(modes, &block)
        end

        def each_package_dependency(modes = Array.new, &block)
            Autoproj.warn "PackageManifest#each_os_dependency called, fix your code"
            return each_dependency(modes, &block)
        end

        def each_rock_maintainer
            return enum_for(__method__) if !block_given?
            xml.elements.each('package/rock_maintainer') do |maintainer|
                (maintainer.text || "").strip.split(',').each do |str|
                    name, email = str.split('/').map(&:strip)
                    email = nil if email && email.empty?
                    yield(name, email)
                end
            end
        end

        def each_maintainer
            return enum_for(__method__) if !block_given?
            xml.elements.each('package/maintainer') do |maintainer|
                (maintainer.text || "").strip.split(',').each do |str|
                    name, email = str.split('/').map(&:strip)
                    email = nil if email && email.empty?
                    yield(name, email)
                end
            end
        end

        # Enumerates the name and email of each author. If no email is present,
        # yields (name, nil)
        def each_author
            if !block_given?
                return enum_for(:each_author)
            end

            xml.elements.each('package/author') do |author|
                (author.text || "").strip.split(',').each do |str|
                    name, email = str.split('/').map(&:strip)
                    email = nil if email && email.empty?
                    yield(name, email)
                end
            end
        end

        # If +name+ points to a text element in the XML document, returns the
        # content of that element. If no element matches +name+, or if the
        # content is empty, returns nil
        def text_node(name)
            xml.elements.each(name) do |str|
                str = (str.text || "").strip
                if !str.empty?
                    return str
                end
            end
            nil
        end

        # The package associated URL, usually meant to direct to a website
        #
        # Returns nil if there is none
        def url
            return text_node('package/url')
        end

        # The package license name
        #
        # Returns nil if there is none
        def license
            return text_node('package/license')
        end

        # The package version number
        #
        # Returns 0 if none is declared
        def version
            return text_node("version")
        end
    end
end
