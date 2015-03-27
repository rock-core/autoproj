module Autoproj
    # Representation of a VCS definition contained in a source.yml file or in
    # autoproj/manifest
    class VCSDefinition
        attr_reader :type
        attr_reader :url
        attr_reader :options

        # The original spec in hash form. Set if this VCSDefinition object has
        # been created using VCSDefinition.from_raw
        attr_reader :raw

        def initialize(type, url, options, raw = nil)
            if raw && !raw.respond_to?(:to_ary)
                raise ArgumentError, "wrong format for the raw field (#{raw.inspect})"
            end

            @type, @url, @options = type, url, options
            if type != "none" && type != "local" && !Autobuild.respond_to?(type)
                raise ConfigError.new, "version control #{type} is unknown to autoproj"
            end
            @raw = raw
        end

        def local?
            @type == 'local'
        end

        def to_hash
            Hash[:type => type, :url => url].merge(options)
        end

        # Update this VCS definition with new information / options and return
        # the updated definition
        #
        # @return [VCSDefinition]
        def update(spec, new_raw_entry)
            new = self.class.vcs_definition_to_hash(spec)
            if new.has_key?(:type) && (type != new[:type])
                # The type changed. We replace the old definition by the new one
                # completely
                self.class.from_raw(new, new_raw_entry)
            else
                self.class.from_raw(to_hash.merge(new), raw + new_raw_entry)
            end
        end

        # Updates the VCS specification +old+ by the information contained in
        # +new+
        #
        # Both +old+ and +new+ are supposed to be in hash form. It is assumed
        # that +old+ has already been normalized by a call to
        # Autoproj.vcs_definition_to_hash. +new+ can be in "raw" form.
        def self.update_raw_vcs_spec(old, new)
            new = vcs_definition_to_hash(new)
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
        def self.vcs_definition_to_hash(spec)
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
                raise ConfigError.new, "invalid syntax"
            elsif plain.size == 1
                short_url = plain.first
                vcs, *url = short_url.split(':')

                # Check if VCS is a known version control system or source handler
                # shortcut. If it is not, look for a local directory called
                # short_url
                if Autobuild.respond_to?(vcs)
                    spec.merge!(:type => vcs, :url => url.join(':'))
                elsif Autoproj.has_source_handler?(vcs)
                    spec = Autoproj.call_source_handler(vcs, url.join(':'), spec)
                else
                    source_dir =
                        if Pathname.new(short_url).absolute?
                            File.expand_path(short_url)
                        else
                            File.expand_path(File.join(Autoproj.config_dir, short_url))
                        end
                    if !File.directory?(source_dir)
                        raise ConfigError.new, "'#{spec.inspect}' is neither a remote source specification, nor an existing local directory"
                    end
                    spec.merge!(:type => 'local', :url => source_dir)
                end
            end

            spec, vcs_options = Kernel.filter_options spec, :type => nil, :url => nil
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

        # Autoproj configuration files accept VCS definitions in three forms:
        #  * as a plain string, which is a relative/absolute path
        #  * as a plain string, which is a vcs_type:url string
        #  * as a hash
        #
        # This method returns the VCSDefinition object matching one of these
        # specs. It raises ConfigError if there is no type and/or url
        def self.from_raw(spec, raw_spec = [[nil, spec]])
            spec = vcs_definition_to_hash(spec)
            if !(spec[:type] && (spec[:type] == 'none' || spec[:url]))
                raise ConfigError.new, "the source specification #{spec.inspect} misses either the VCS type or an URL"
            end

            spec, vcs_options = Kernel.filter_options spec, :type => nil, :url => nil
            return VCSDefinition.new(spec[:type], spec[:url], vcs_options, raw_spec)
        end

        def ==(other_vcs)
            return false if !other_vcs.kind_of?(VCSDefinition)
            if local?
                other_vcs.local? && url == other.url
            elsif !other_vcs.local?
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

        def self.to_absolute_url(url, root_dir = nil)
            # NOTE: we MUST use nil as default argument of root_dir as we don't
            # want to call Autoproj.root_dir unless completely necessary
            # (to_absolute_url might be called on installations that are being
            # bootstrapped, and as such don't have a root dir yet).
            url = Autoproj.single_expansion(url, 'HOME' => ENV['HOME'])
            if url && url !~ /^(\w+:\/)?\/|^[:\w]+\@|^(\w+\@)?[\w\.-]+:/
                url = File.expand_path(url, root_dir || Autoproj.root_dir)
            end
            url
        end

        # Whether the underlying package needs to be imported
        def needs_import?
            type != 'none' && type != 'local'
        end

        # Returns a properly configured instance of a subclass of
        # Autobuild::Importer that match this VCS definition
        #
        # @return [Autobuild::Importer,nil] the autobuild importer
        def create_autobuild_importer
            return if !needs_import?

            url = VCSDefinition.to_absolute_url(self.url)
            Autobuild.send(type, url, options)
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

    # call-seq:
    #   Autoproj.add_source_handler name do |url, options|
    #     # build a hash that represent source configuration
    #     # and return it
    #   end
    #
    # Add a custom source handler named +name+
    #
    # Custom source handlers are shortcuts that can be used to represent VCS
    # information. For instance, the gitorious_server_configuration method
    # defines a source handler that allows to easily add new gitorious packages:
    #
    #   gitorious_server_configuration 'GITORIOUS', 'gitorious.org'
    #
    # defines the "gitorious" source handler, which allows people to write
    #
    #
    #   version_control:
    #       - tools/orocos.rb
    #         gitorious: rock-toolchain/orocos-rb
    #         branch: test
    #
    # 
    def self.add_source_handler(name, &handler)
        @custom_source_handlers[name.to_s] = lambda(&handler)
    end
end
