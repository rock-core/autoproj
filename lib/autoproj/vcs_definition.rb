module Autoproj
    # Representation of a VCS definition contained in a source.yml file or in
    # autoproj/manifest
    class VCSDefinition
        # The VCS type
        #
        # @return [Symbol]
        attr_reader :type

        # The VCS URL
        #
        # @return [String]
        attr_reader :url

        # The VCS options
        #
        # @return [Hash]
        attr_reader :options

        # This VCSDefinition history
        #
        # i.e. the list of VCSDefinition objects that led to this one by means
        # of calls to {#update}
        #
        # @return [Array<HistoryEntry>]
        attr_reader :history

        # The original spec in hash form
        #
        # @return [Array<RawEntry>]
        attr_reader :raw

        HistoryEntry  = Struct.new :package_set, :vcs
        RawEntry      = Struct.new :package_set, :file, :vcs

        def initialize(type, url, vcs_options, from: nil, raw: Array.new, history: Array.new)
            if !raw.respond_to?(:to_ary)
                raise ArgumentError, "wrong format for the raw field (#{raw.inspect})"
            end

            @type, @url, @options = type, url, vcs_options
            if type != "none" && type != "local" && !Autobuild.respond_to?(type)
                raise ConfigError.new, "version control #{type} is unknown to autoproj"
            end

            @history = history + [HistoryEntry.new(from, self)]
            @raw     = raw
        end

        # Create a null VCS object
        def self.none
            from_raw(type: 'none')
        end

        # Whether there is actually a version control definition
        def none?
            @type == 'none'
        end

        # Whether this points to a local directory
        def local?
            @type == 'local'
        end

        # Converts self to a Hash description that could be passed to {.from_raw}
        #
        # @return [Hash]
        def to_hash
            Hash[type: type, url: url].merge(options)
        end

        # Update this VCS definition with new information / options and return
        # the updated definition
        #
        # @return [VCSDefinition]
        def update(spec, from: nil, raw: Array.new)
            new = self.class.normalize_vcs_hash(spec)
            new_raw = Array.new
            new_history = Array.new

            # If the type changed, we replace the old definition by the new one
            # completely. Otherwise, we append it to the current one
            if !new.has_key?(:type) || (type == new[:type])
                new = to_hash.merge(new)
                new_raw = self.raw + raw
                new_history = self.history
            end
            self.class.from_raw(new, from: from, history: new_history, raw: new_raw)
        end

        # Updates the VCS specification +old+ by the information contained in
        # +new+
        #
        # Both +old+ and +new+ are supposed to be in hash form. It is assumed
        # that +old+ has already been normalized by a call to
        # {.normalize_vcs_hash}. +new+ can be in "raw" form.
        def self.update_raw_vcs_spec(old, new)
            new = normalize_vcs_hash(new)
            if new.has_key?(:type) && (old[:type] != new[:type])
                # The type changed. We replace the old definition by the new one
                # completely, and we make sure that the new definition is valid
                from_raw(new)
                new
            else
                old.merge(new)
            end
        end

        # Normalizes a VCS definition contained in a YAML file into a hash
        #
        # It handles custom source handler expansion, as well as the bad habit
        # of forgetting a ':' at the end of a line:
        #
        #   - package_name
        #     branch: value
        #
        # @raise ArgumentError if the given spec cannot be normalized
        def self.normalize_vcs_hash(spec, base_dir: nil)
            plain = Array.new
            filtered_spec = Hash.new

            if spec.respond_to?(:to_str)
                plain << spec
                spec = Hash.new
            else
                Array(spec).each do |key, value|
                    keys = key.to_s.split(/\s+/)
                    plain.concat(keys[0..-2])
                    filtered_spec[keys[-1].to_sym] = value
                end
                spec = filtered_spec
            end

            if plain.size > 1
                raise ArgumentError, "invalid syntax"
            elsif plain.size == 1
                short_url = plain.first
                vcs, *url = short_url.split(':')

                # Check if VCS is a known version control system or source handler
                # shortcut. If it is not, look for a local directory called
                # short_url
                if Autobuild.respond_to?(vcs)
                    spec.merge!(type: vcs, url: url.join(':'))
                elsif Autoproj.has_source_handler?(vcs)
                    spec = Autoproj.call_source_handler(vcs, url.join(':'), spec)
                else
                    source_dir =
                        if Pathname.new(short_url).absolute?
                            File.expand_path(short_url)
                        elsif base_dir
                            File.expand_path(short_url, base_dir)
                        else
                            raise ArgumentError, "VCS path '#{short_url}' is relative and no base_dir was given"
                        end
                    if !File.directory?(source_dir)
                        raise ArgumentError, "'#{short_url}' is neither a remote source specification, nor an existing local directory"
                    end
                    spec.merge!(type: 'local', url: source_dir)
                end
            end

            spec, vcs_options = Kernel.filter_options spec, type: nil, url: nil
            spec.merge!(vcs_options)
            if !spec[:url]
                # Verify that none of the keys are source handlers. If it is the
                # case, convert
                filtered_spec = Hash.new
                spec.dup.each do |key, value|
                    if Autoproj.has_source_handler?(key)
                        spec.delete(key)
                        spec = Autoproj.call_source_handler(key, value, spec)
                        break
                    end
                end
            end

            spec
        end

        # @api private
        #
        # Converts a raw spec (a hash, really) into a nicely formatted string
        def self.raw_spec_to_s(spec)
            "{ #{spec.sort_by(&:first).map { |k, v| "#{k}: #{v}" }.join(", ")} }"
        end

        # Converts a 'raw' VCS representation to a normalized hash.
        #
        # The raw definition can have three forms:
        #  * as a plain string, which is a relative/absolute path
        #  * as a plain string, which is a vcs_type:url string
        #  * as a hash
        #
        # @return [VCSDefinition]
        # @raise ArgumentError if the raw specification does not match an
        #   expected format
        def self.from_raw(spec, from: nil, raw: Array.new, history: Array.new)
            normalized_spec = normalize_vcs_hash(spec)
            if !(type = normalized_spec.delete(:type))
                raise ArgumentError, "the source specification #{raw_spec_to_s(spec)} normalizes into #{raw_spec_to_s(normalized_spec)}, which does not have a VCS type"
            elsif !(url  = normalized_spec.delete(:url))
                if type != 'none'
                    raise ArgumentError, "the source specification #{raw_spec_to_s(spec)} normalizes into #{raw_spec_to_s(normalized_spec)}, which does not have a URL. Only VCS of type 'none' do not require one"
                end
            end

            VCSDefinition.new(type, url, normalized_spec, from: from, history: history, raw: raw)
        end

        def ==(other_vcs)
            return false if !other_vcs.kind_of?(VCSDefinition)
            if local?
                other_vcs.local? && url == other_vcs.url
            elsif other_vcs.local?
                false
            elsif none?
                other_vcs.none?
            elsif other_vcs.none?
                false
            else
                this_importer = create_autobuild_importer
                other_importer = other_vcs.create_autobuild_importer
                this_importer.source_id == other_importer.source_id
            end
        end

        def hash
            to_hash.hash
        end

        def eql?(other_vcs)
            to_hash == other_vcs.to_hash
        end

        ABSOLUTE_PATH_OR_URI = /^([\w+]+:\/)?\/|^[:\w]+\@|^(\w+\@)?[\w\.-]+:/

        def self.to_absolute_url(url, root_dir)
            if url && url !~ ABSOLUTE_PATH_OR_URI
                url = File.expand_path(url, root_dir)
            end
            url
        end

        # Whether the underlying package needs to be imported
        def needs_import?
            type != 'none' && type != 'local'
        end

        def overrides_key
            return if none?
            if local?
                "local:#{url}"
            else
                create_autobuild_importer.repository_id
            end
        end

        # Returns a properly configured instance of a subclass of
        # Autobuild::Importer that match this VCS definition
        #
        # @return [Autobuild::Importer,nil] the autobuild importer
        def create_autobuild_importer
            return if !needs_import?

            importer = Autobuild.send(type, url, options)
            if importer.respond_to?(:declare_alternate_repository)
                history.each do |entry|
                    package_set = entry.package_set
                    vcs         = entry.vcs
                    next if !package_set || package_set.main?
                    importer.declare_alternate_repository(package_set.name, vcs.url, vcs.options)
                end
            end
            importer
        end

        # Returns a pretty representation of this VCS definition
        def to_s
            if type == "none"
                "none"
            else
                desc = "#{type}:#{url}"
                if !options.empty?
                    desc = "#{desc} #{options.to_a.sort_by { |key, _| key.to_s }.map { |key, value| "#{key}=#{value}" }.join(" ")}"
                end
                desc
            end
        end
    end

    @custom_source_handlers = Hash.new

    # Returns true if +vcs+ refers to a source handler name added by
    # #add_source_handler
    def self.has_source_handler?(vcs)
        @custom_source_handlers.has_key?(vcs.to_s)
    end

    # Returns the source handlers associated with +vcs+
    #
    # Source handlers are added by Autoproj.add_source_handler. The returned
    # value is an object that responds to #call(url, options) and return a VCS
    # definition as a hash
    def self.call_source_handler(vcs, url, options)
        handler = @custom_source_handlers[vcs.to_s]
        if !handler
            raise ArgumentError, "there is no source handler for #{vcs}"
        else
            return handler.call(url, options)
        end
    end

    # Add a custom source handler named +name+
    #
    # Custom source handlers are shortcuts that can be used to represent VCS
    # information. For instance, the {Autoproj.git_server_configuration} helper defines a
    # source handler that allows to easily add new github packages:
    #
    #   Autoproj.git_server_configuration('GITHUB', 'github.com',
    #      http_url: 'https://github.com',
    #      default: 'http,ssh')
    #
    # Defines a 'github' custom handler that expands into the full VCS
    # configuration to access github
    #
    #   version_control:
    #       - tools/orocos.rb:
    #         github: rock-core/base-types
    #         branch: test
    #
    # @yieldparam [String] url the url given to the handler
    # @yieldparam [Hash] the rest of the VCS hash
    # @return [Hash] a VCS hash with the information expanded
    def self.add_source_handler(name, &handler)
        @custom_source_handlers[name.to_s] = lambda(&handler)
    end

    # Deregister a source handler defined with {.add_source_handler}
    def self.remove_source_handler(name)
        @custom_source_handlers.delete(name)
    end
end
