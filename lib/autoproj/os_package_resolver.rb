require 'tempfile'
require 'json'

module Autoproj
    # Manager for packages provided by external package managers
    class OSPackageResolver
        def self.load(file, suffixes: [], **options)
            unless File.file?(file)
                raise ArgumentError, "no such file or directory #{file}"
            end

            candidates = [file]
            candidates.concat(suffixes.map { |s| "#{file}-#{s}" })

            error_t =
                if defined? Psych::SyntaxError
                    [ArgumentError, Psych::SyntaxError]
                else ArgumentError
                end

            result = new(**options)
            candidates.each do |file_candidate|
                next unless File.file?(file_candidate)

                file_candidate = File.expand_path(file_candidate)
                begin
                    data = YAML.safe_load(File.read(file_candidate)) || Hash.new
                    verify_definitions(data)
                rescue *error_t => e
                    raise ConfigError.new, "error in #{file_candidate}: "\
                        "#{e.message}", e.backtrace
                end

                result.merge(new(data, file_candidate, **options))
            end
            result
        end

        # The underlying workspace
        attr_reader :ws

        def self.autodetect_ruby_program
            ruby = RbConfig::CONFIG['RUBY_INSTALL_NAME']
            ruby_bindir = RbConfig::CONFIG['bindir']
            ruby_executable = File.join(ruby_bindir, ruby)
            Autobuild.programs['ruby'] = ruby_executable
            ruby_executable
        end

        AUTOPROJ_OSDEPS = File.join(__dir__, 'default.osdeps')
        def self.load_default
            file = ENV['AUTOPROJ_DEFAULT_OSDEPS'] || AUTOPROJ_OSDEPS
            unless File.file?(file)
                Autoproj.warn "#{file} (from AUTOPROJ_DEFAULT_OSDEPS) is not a file, "\
                    "falling back to #{AUTOPROJ_OSDEPS}"
                file = AUTOPROJ_OSDEPS
            end
            load(file)
        end

        def load_default
            merge(self.class.load_default)
        end

        PACKAGE_MANAGERS = OSPackageInstaller::PACKAGE_MANAGERS.keys

        # Mapping from OS name to package manager name
        #
        # Package handlers and OSes MUST have different names. The former are
        # used to resolve packages and the latter to resolve OSes in the osdeps.
        # Since one can force the use of a package manager in any OS by adding a
        # package manager entry, as e.g.
        #
        # ubuntu:
        #    homebrew: package
        #
        # we need to be able to separate between OS and package manager names.
        OS_PACKAGE_MANAGERS = {
            'debian' => 'apt-dpkg',
            'gentoo' => 'emerge',
            'arch' => 'pacman',
            'fedora' => 'yum',
            'macos-port' => 'macports',
            'macos-brew' => 'brew',
            'opensuse' => 'zypper',
            'freebsd' => 'pkg'
        }.freeze

        # The information contained in the OSdeps files, as a hash
        attr_reader :definitions
        # All the information contained in all the OSdeps files, as a mapping
        # from the OSdeps package name to [osdeps_file, definition] pairs
        attr_reader :all_definitions
        # The information as to from which osdeps file the current package
        # information in +definitions+ originates. It is a mapping from the
        # package name to the osdeps file' full path
        attr_reader :sources
        # Controls whether the package resolver will prefer installing
        # OS-independent packages (such as e.g. Gems) over their OS-provided
        # equivalent (e.g. the packaged version of a gem)
        def prefer_indep_over_os_packages?
            @prefer_indep_over_os_packages
        end
        # (see prefer_indep_over_os_packages?)
        attr_writer :prefer_indep_over_os_packages
        # Cached results of {#resolve_package}
        attr_reader :resolve_package_cache

        # Use to override the autodetected OS-specific package handler
        def os_package_manager=(manager_name)
            if manager_name && !package_managers.include?(manager_name)
                raise ArgumentError, "#{manager_name} is not a known "\
                    "package manager, known managers are "\
                    "#{package_managers.to_a.sort.join(', ')}"
            end
            @os_package_manager = manager_name
        end

        # Returns the name of the package manager object for the current OS
        #
        # @return [String]
        def os_package_manager
            unless @os_package_manager
                os_names, = operating_system
                os_name = os_names.find { |name| OS_PACKAGE_MANAGERS[name] }
                @os_package_manager = OS_PACKAGE_MANAGERS[os_name] || 'unknown'
            end
            @os_package_manager
        end

        # Returns the set of known package managers
        #
        # @return [Array<String>]
        attr_reader :package_managers

        # Aliases for osdep packages
        attr_reader :aliases

        # The Gem::SpecFetcher object that should be used to query RubyGems, and
        # install RubyGems packages
        def initialize(defs = Hash.new, file = nil,
                       operating_system: nil,
                       package_managers: PACKAGE_MANAGERS.dup,
                       os_package_manager: nil)
            @definitions = defs.to_hash
            @resolve_package_cache = Hash.new
            @all_definitions = Hash.new { |h, k| h[k] = Array.new }
            @package_managers = package_managers
            self.os_package_manager = os_package_manager

            @prefer_indep_over_os_packages = false
            @aliases = Hash.new

            @sources = Hash.new
            @installed_packages = Set.new
            @operating_system = operating_system
            @supported_operating_system = nil
            @odeps_mode = nil
            if file
                defs.each_key do |package_name|
                    sources[package_name] = file
                    all_definitions[package_name] << [[file], defs[package_name]]
                end
            else
                defs.each_key do |package_name|
                    all_definitions[package_name] << [[], defs[package_name]]
                end
            end
        end

        # Register new aliases
        #
        # @param [String=>String] new_aliases mapping of the alias to the exact
        #   name
        def add_aliases(new_aliases)
            aliases.merge!(new_aliases)
        end

        # Returns the name of all known OS packages
        #
        # It includes even the packages for which there are no definitions on
        # this OS
        def all_package_names
            definitions.keys
        end

        # Returns the full path to the osdeps file from which the package
        # definition for +package_name+ has been taken
        def source_of(package_name)
            sources[package_name]
        end

        def add_entries(entries, file: nil)
            merge(self.class.new(entries, file))
        end

        def invalidate_resolve_package_cache
            @resolve_package_cache.clear
        end

        # Merges the osdeps information of +info+ into +self+. If packages are
        # defined in both OSPackageResolver objects, the information in +info+
        # takes precedence
        def merge(info, suffixes: [])
            @definitions = definitions.merge(info.definitions) do |h, v1, v2|
                warn_about_merge_collisions(info, suffixes, h, v1, v2) if v1 != v2
                v2
            end
            invalidate_resolve_package_cache

            @sources = sources.merge(info.sources)
            @all_definitions = all_definitions.
                merge(info.all_definitions) do |_package_name, all_defs, new_all_defs|
                    all_defs = all_defs.dup
                    new_all_defs = new_all_defs.dup
                    new_all_defs.delete_if do |files, data|
                        if (entry = all_defs.find { |_, d| d == data })
                            entry[0] |= files
                        end
                    end
                    all_defs.concat(new_all_defs)
                end
        end

        # @api private
        #
        # Warn about a collision (override) detected during #merge
        def warn_about_merge_collisions(merged_info, suffixes, key,
                                        _old_value, _new_value)
            old = source_of(key)
            new = merged_info.source_of(key)

            return if suffixes.any? { |s| new == "#{old}#{s}" }

            # Warn if the new osdep definition resolves to a different
            # set of packages than the old one
            old_resolved = resolve_package(key, resolve_recursive: false).
                each_with_object(Hash.new) do |(handler, status, list), osdep_h|
                    osdep_h[handler] = [status, list.dup]
                end
            new_resolved = merged_info.resolve_package(key, resolve_recursive: false).
                each_with_object(Hash.new) do |(handler, status, list), osdep_h|
                    osdep_h[handler] = [status, list.dup]
                end
            if old_resolved != new_resolved
                Autoproj.warn "osdeps definition for #{key}, "\
                    "previously defined in #{old} overridden by #{new}:"
                first = true
                old_resolved.each do |handler, (_, packages)|
                    Autoproj.warn "  #{first ? 'resp. ' : '      '}#{handler}: "\
                        "#{packages.map(&:to_s).join(', ')}"
                    first = false
                end
                first = true
                new_resolved.each do |handler, (_, packages)|
                    Autoproj.warn "  #{first ? 'and   ' : '      '}#{handler}: "\
                        "#{packages.map(&:to_s).join(', ')}"
                    first = false
                end
            end
        end

        # Perform some sanity checks on the given osdeps definitions
        def self.verify_definitions(hash, path = [])
            hash.each do |key, value|
                if value && !key.kind_of?(String)
                    raise ArgumentError, "invalid osdeps definition: "\
                        "found an #{key.class} as a key in #{path.join('/')}. "\
                        "Don't forget to put quotes around numbers"
                elsif !value && (key.kind_of?(Hash) || key.kind_of?(Array))
                    verify_definitions(key)
                end
                next unless value

                if value.kind_of?(Array) || value.kind_of?(Hash)
                    verify_definitions(value, (path + [key]))
                elsif !value.kind_of?(String)
                    raise ArgumentError, "invalid osdeps definition: "\
                        "found an #{value.class} as a value in #{path.join('/')}. "\
                        "Don't forget to put quotes around numbers"
                end
            end
        end

        # Whether the operating system could be autodetected successfully
        def known_operating_system?
            os_names, = operating_system
            !os_names.empty?
        end

        # Returns true if it is possible to install packages for the operating
        # system on which we are installed
        def supported_operating_system?
            if @supported_operating_system.nil?
                @supported_operating_system = (os_package_manager != 'unknown')
            end
            @supported_operating_system
        end

        def self.guess_operating_system
            if File.exist?('/etc/debian_version')
                versions = [File.read('/etc/debian_version').strip]
                versions = %w[unstable sid] if versions.first =~ /sid/
                [['debian'], versions]
            elsif File.exist?('/etc/redhat-release')
                release_string = File.read('/etc/redhat-release').strip
                release_string =~ /(.*) release ([\d.]+)/
                name = $1.downcase
                version = $2
                name = 'rhel' if name =~ /Red Hat Entreprise/
                [[name], [version]]
            elsif File.exist?('/etc/gentoo-release')
                release_string = File.read('/etc/gentoo-release').strip
                release_string =~ /^.*([^\s]+)$/
                version = $1
                [['gentoo'], [version]]
            elsif File.exist?('/etc/arch-release')
                [['arch'], []]
            elsif Autobuild.macos?
                version = `sw_vers | head -2 | tail -1`.split(":")[1]
                manager =
                    ENV['AUTOPROJ_MACOSX_PACKAGE_MANAGER'] ||
                    'macos-brew'
                unless OS_PACKAGE_MANAGERS.key?(manager)
                    known_managers = OS_PACKAGE_MANAGERS.keys.grep(/^macos/)
                    raise ArgumentError, "#{manager} is not a known MacOSX "\
                        "package manager. Known package managers are "\
                        "#{known_managers.join(', ')}"
                end

                managers =
                    if manager == 'macos-port'
                        [manager, 'port']
                    else [manager]
                    end
                [[*managers, 'darwin'], [version.strip]]
            elsif Autobuild.windows?
                [['windows'], []]
            elsif File.exist?('/etc/SuSE-release')
                version = File.read('/etc/SuSE-release').strip
                version =~ /.*VERSION\s+=\s+([^\s]+)/
                version = $1
                [['opensuse'], [version.strip]]
            elsif Autobuild.freebsd?
                version = `uname -r`.strip.split("-")[0]
                [['freebsd'], [version]]
            end
        end

        def self.ensure_derivatives_refer_to_their_parents(names)
            names = names.dup
            version_files = Hash[
                '/etc/debian_version' => 'debian',
                '/etc/redhat-release' => 'fedora',
                '/etc/gentoo-release' => 'gentoo',
                '/etc/arch-release' => 'arch',
                '/etc/SuSE-release' => 'opensuse']
            version_files.each do |file, name|
                names << name if File.exist?(file) && !names.include?(name)
            end
            names
        end

        def self.normalize_os_representation(names, versions)
            # Normalize the names to lowercase
            names    = names.map(&:downcase)
            versions = versions.map(&:downcase)
            versions += ['default'] unless versions.include?('default')
            [names, versions]
        end

        # The operating system self is targetting
        #
        # If unset in {#initialize} or by calling {#operating_system=}, it will
        # attempt to autodetect it on the first call
        def operating_system
            @operating_system ||= self.class.autodetect_operating_system
        end

        # Change the operating system this resolver is targetting
        def operating_system=(values)
            @supported_operating_system = nil
            @os_package_manager = nil
            @operating_system = values
        end

        # Autodetects the operating system name and version
        #
        # +osname+ is the operating system name, all in lowercase (e.g. ubuntu,
        # arch, gentoo, debian)
        #
        # +versions+ is a set of names that describe the OS version. It includes
        # both the version number (as a string) and/or the codename if there is
        # one.
        #
        # Examples: ['debian', ['sid', 'unstable']] or ['ubuntu', ['lucid lynx', '10.04']]
        def self.autodetect_operating_system
            if (user_os = ENV['AUTOPROJ_OS'])
                if user_os.empty?
                    return false
                else
                    names, versions = user_os.split(':')
                    return normalize_os_representation(
                        names.split(','), versions.split(','))
                end
            end

            names, versions = os_from_os_release
            names, versions = guess_operating_system unless names

            # on Debian, they refuse to put enough information to detect
            # 'unstable' reliably. So, we use the heuristic method for it
            if names[0] == "debian"
                # check if we actually got a debian with the "unstable" (sid)
                # flavour. it seems that "/etc/debian_version" does not contain
                # "sid" (but "8.0" for example) during the feature freeze
                # phase...
                if File.exist?('/etc/debian_version')
                    debian_versions = [File.read('/etc/debian_version').strip]
                    versions = %w[unstable sid] if debian_versions.first =~ /sid/
                end
                # otherwise "versions" contains the result it previously had
            end
            return unless names

            names = ensure_derivatives_refer_to_their_parents(names)
            names, versions = normalize_os_representation(names, versions)
            [names, versions]
        end

        def self.os_from_os_release(filename = '/etc/os-release')
            return unless File.exist?(filename)

            fields = Hash.new
            File.readlines(filename).each do |line|
                line = line.strip
                if line.strip =~ /^(\w+)=(?:["'])?([^"']+)(?:["'])?$/
                    fields[$1] = $2
                elsif !line.empty?
                    Autoproj.warn "could not parse line '#{line.inspect}' "\
                        "in /etc/os-release"
                end
            end

            names = []
            versions = []
            names << fields['ID'] << fields['ID_LIKE']
            versions << fields['VERSION_ID']
            version = fields['VERSION'] || ''
            versions.concat(version.gsub(/[^\w.]/, ' ').split(' '))
            [names.compact.uniq, versions.compact.uniq]
        end

        def self.os_from_lsb
            return unless Autobuild.find_in_path('lsb_release')

            distributor = [`lsb_release -i -s`.strip.downcase]
            codename    = `lsb_release -c -s`.strip.downcase
            version     = `lsb_release -r -s`.strip.downcase

            [distributor, [codename, version]]
        end

        class InvalidRecursiveStatement < Autobuild::Exception; end

        # Return the path to the osdeps name for a given package name while
        # accounting for package aliases
        #
        # returns an array contain the path starting with name and
        # ending at the resolved name
        def resolve_name(name)
            path = [name]
            while aliases.key?(name)
                name = aliases[name]
                path << name
            end
            path
        end

        # Null object class that is used to mark recursive resolution when
        # calling {#resolve_package} with resolve_recursive set to false
        class OSDepRecursiveResolver
            def self.to_s
                'osdep'.freeze
            end
        end

        # Return the list of packages that should be installed for +name+
        #
        # The following two simple return values are possible:
        #
        # nil:: +name+ has no definition
        # []:: +name+ has no definition on this OS and/or for this specific OS
        #      version
        #
        # In all other cases, the method returns an array of triples:
        #
        #   [package_handler, status, package_list]
        #
        # where status is FOUND_PACKAGES if +package_list+ is the list of
        # packages that should be installed with +package_handler+ for +name+,
        # and FOUND_NONEXISTENT if the nonexistent keyword is used for this OS
        # name and version. The package list might be empty even if status ==
        # FOUND_PACKAGES, for instance if the ignore keyword is used.
        def resolve_package(name, resolve_recursive: true)
            return resolve_package_cache[name] if resolve_package_cache.key?(name)

            path = resolve_name(name)
            name = path.last

            dep_def = definitions[name]
            return (resolve_package_cache[name] = nil) unless dep_def

            os_names, os_versions = operating_system

            # Partition the found definition in all entries that are interesting
            # for us: toplevel os-independent package managers, os-dependent
            # package managers and os-independent package managers selected by
            # OS or version
            if os_names.empty?
                os_names = ['default']
                os_versions = ['default']
            else
                os_names = os_names.dup
                if prefer_indep_over_os_packages?
                    os_names.unshift 'default'
                else
                    os_names.push 'default'
                end
            end

            result = []
            found, pkg = partition_osdep_entry(
                name, dep_def, nil,
                (package_managers - [os_package_manager]), os_names, os_versions)
            result << [os_package_manager, found, pkg] if found

            package_managers.each do |handler|
                found, pkg = partition_osdep_entry(
                    name, dep_def, [handler], [], os_names, os_versions)
                result << [handler, found, pkg] if found
            end

            # Recursive resolutions
            found, pkg = partition_osdep_entry(
                name, dep_def, ['osdep'], [], os_names, os_versions)
            if found
                if resolve_recursive
                    pkg.each do |pkg_name|
                        resolved = resolve_package(pkg_name)
                        unless resolved
                            raise InvalidRecursiveStatement, "the '#{name}' osdep "\
                                "refers to another osdep, '#{pkg_name}', which "\
                                "does not seem to exist"
                        end
                        result.concat(resolved)
                    end
                else
                    result << [OSDepRecursiveResolver, found, pkg]
                end
            end

            result.each do |args|
                args.last.freeze
            end
            result.freeze
            if resolve_recursive
                resolve_package_cache[name] = result
            else
                result
            end
        end

        # Value returned by #resolve_package and #partition_osdep_entry in
        # the status field. See the documentation of these methods for more
        # information
        FOUND_PACKAGES = 0
        # Value returned by #resolve_package and #partition_osdep_entry in
        # the status field. See the documentation of these methods for more
        # information
        FOUND_NONEXISTENT = 1

        # Helper method that parses the osdep definition to split between the
        # parts needed for this OS and specific package handlers.
        #
        # +osdep_name+ is the name of the osdep. It is used to resolve explicit
        # mentions of a package handler, i.e. so that:
        #
        #   pkg: gem
        #
        # is resolved as the 'pkg' package to be installed by the 'gem' handler
        #
        # +dep_def+ is the content to parse. It can be a string, array or hash
        #
        # +handler_names+ is a list of entries that we are looking for. If it is
        # not nil, only entries that explicitely refer to +handler_names+ will
        # be browsed, i.e. in:
        #
        #   pkg:
        #       - test: 1
        #       - [a, list, of, packages]
        #
        #   partition_osdep_entry('osdep_name', data, ['test'], [])
        #
        # will ignore the toplevel list of packages, while
        #
        #   partition_osdep_entry('osdep_name', data, nil, [])
        #
        # will return it.
        #
        # +excluded+ is a list of branches that should be ignored during
        # parsing. It is used to e.g. ignore 'gem' when browsing for the main OS
        # package list. For instance, in
        #
        #   pkg:
        #       - test
        #       - [a, list, of, packages]
        #
        #   partition_osdep_entry('osdep_name', data, nil, ['test'])
        #
        # the returned value will only include the list of packages (and not
        # 'test')
        #
        # The rest of the arguments are array of strings that contain list of
        # keys to browse for (usually, the OS names and version)
        #
        # The return value is either nil if no packages were found, or a pair
        # [status, package_list] where status is FOUND_NONEXISTENT if the
        # nonexistent keyword was found, and FOUND_PACKAGES if either packages
        # or the ignore keyword were found.
        #
        def partition_osdep_entry(osdep_name, dep_def, handler_names, excluded, *keys)
            keys, *additional_keys = *keys
            keys ||= []
            found = false
            nonexistent = false
            result = []
            found_keys = Hash.new
            Array(dep_def).each do |names, values|
                if !values
                    entry_found, entry_nonexistent, entry_names =
                        partition_osdep_raw_array_entry(names, osdep_name,
                            handler_names, excluded, keys, additional_keys)
                else
                    entry_found, entry_nonexistent, entry_names =
                        partition_osdep_map_entry(names, values, osdep_name,
                            handler_names, excluded, keys, found_keys, additional_keys)
                end
                found ||= entry_found
                nonexistent ||= entry_nonexistent
                result.concat(entry_names)
            end

            first_entry = found_keys.keys.min
            found_keys = found_keys[first_entry]
            if found_keys
                if found_keys[0] > 0
                    nonexistent = true
                else
                    found = true
                end
                result.concat(found_keys[1])
            end

            found =
                if nonexistent then FOUND_NONEXISTENT
                elsif found then FOUND_PACKAGES
                else false
                end

            [found, result]
        end

        def partition_osdep_raw_array_entry(names, osdep_name, handler_names,
                                            excluded, keys, additional_keys)
            have_handler_names = true if handler_names

            # Raw array of packages. Possible only if we are not at toplevel
            # (i.e. if we already have a handler)
            if names == 'ignore'
                [!have_handler_names, false, []]
            elsif names == 'nonexistent'
                [false, !have_handler_names, []]
            elsif !handler_names && names.kind_of?(Array)
                [true, false, names]
            elsif names.respond_to?(:to_str)
                if excluded.include?(names)
                    [false, false, []]
                elsif handler_names&.include?(names)
                    [true, false, [osdep_name]]
                elsif !handler_names
                    [true, false, [names]]
                else
                    [false, false, []]
                end
            elsif names.respond_to?(:to_hash)
                rec_found, rec_result = partition_osdep_entry(osdep_name,
                    names, handler_names, excluded, keys, *additional_keys)
                if rec_found == FOUND_NONEXISTENT
                    [false, true, rec_result]
                elsif rec_found == FOUND_PACKAGES
                    [true, false, rec_result]
                else
                    [false, false, []]
                end
            else
                [false, false, []]
            end
        end

        def partition_osdep_map_entry(names, values, osdep_name, handler_names,
                                      excluded, keys, found_keys, additional_keys)
            # names could be an array already
            names = names.split(',') if names.respond_to?(:to_str)
            result = [false, false, []]

            if handler_names
                matching_handler = handler_names.
                    find { |k| names.any? { |name_tag| k == name_tag.downcase } }
                if matching_handler
                    rec_found, rec_result = partition_osdep_entry(
                        osdep_name, values, nil, excluded, keys, *additional_keys)
                    if rec_found == FOUND_NONEXISTENT
                        result = [false, true, rec_result]
                    elsif rec_found == FOUND_PACKAGES
                        result = [true, false, rec_result]
                    end
                end
            end

            matching_name = keys.
                find { |k| names.any? { |name_tag| k == name_tag.downcase } }
            return result unless matching_name

            rec_found, rec_result = partition_osdep_entry(
                osdep_name, values, handler_names, excluded, *additional_keys)
            # We only consider the first highest-priority entry,
            # regardless of whether it has some packages for us or
            # not
            idx = keys.index(matching_name)
            if !rec_found
                found_keys[idx] = nil unless found_keys.key?(idx)
            else
                found_keys[idx] ||= [0, []]
                found_keys[idx][0] += rec_found
                found_keys[idx][1].concat(rec_result)
            end
            result
        end

        # Resolves the given OS dependencies into the actual packages that need
        # to be installed on this particular OS.
        #
        # @param [Array<String>] dependencies the list of osdep names that
        #   should be resolved
        # @return [Array<#install,Array<String>>] the set of packages, grouped
        #   by the package handlers that should be used to install them
        #
        # @raise MissingOSDep if some packages can't be found or if the
        #   nonexistent keyword was found for some of them
        def resolve_os_packages(dependencies)
            all_packages = []
            dependencies.each do |name|
                result = resolve_package(name)
                unless result
                    path = resolve_name(name)
                    raise MissingOSDep.new, "there is no osdeps definition "\
                        "for #{path.last} (search tree: #{path.join('->')})"
                end

                if result.empty?
                    os_names, os_versions = operating_system
                    if os_names.empty?
                        raise MissingOSDep.new, "there is an osdeps "\
                            "definition for #{name}, but autoproj cannot "\
                            "detect the local operation system"
                    else
                        raise MissingOSDep.new, "there is an osdeps "\
                            "definition for #{name}, but not for this "\
                            "operating system and version resp. "\
                            "#{os_names.join(', ')} and #{os_versions.join(', ')})"
                    end
                end

                result.each do |handler, status, packages|
                    if status == FOUND_NONEXISTENT
                        raise MissingOSDep.new, "there is an osdep "\
                            "definition for #{name}, and it explicitely "\
                            "states that this package does not exist on your OS"
                    end
                    if (entry = all_packages.find { |h, _| h == handler })
                        entry[1].concat(packages)
                    else
                        all_packages << [handler, packages.dup]
                    end
                end
            end

            all_packages.delete_if do |_handler, pkg|
                pkg.empty?
            end
            all_packages
        end

        # Returns true if the given name has an entry in the osdeps
        def include?(name)
            definitions.key?(name)
        end

        # Returns true if +name+ is an acceptable OS package for this OS and
        # version
        def has?(name)
            status = availability_of(name)
            [AVAILABLE, IGNORE].include?(status)
        end

        # Value returned by #availability_of if the required package has no
        # definition
        NO_PACKAGE       = 0
        # Value returned by #availability_of if the required package has
        # definitions, but not for this OS name or version
        WRONG_OS         = 1
        # Value returned by #availability_of if the required package has
        # definitions, but the local OS is unknown
        UNKNOWN_OS       = 2
        # Value returned by #availability_of if the required package has
        # definitions, but the nonexistent keyword was used for this OS
        NONEXISTENT      = 3
        # Value returned by #availability_of if the required package is
        # available
        AVAILABLE        = 4
        # Value returned by #availability_of if the required package is
        # available, but no package needs to be installed to have it
        IGNORE           = 5

        # If +name+ is an osdeps that is available for this operating system,
        # returns AVAILABLE. Otherwise, returns one of:
        #
        # NO_PACKAGE:: the package has no definitions
        # WRONG_OS:: the package has a definition, but not for this OS
        # UNKNOWN_OS:: the package has a definition, but the local OS is unknown
        # NONEXISTENT:: the package has a definition, but the 'nonexistent'
        #               keyword was found for this OS
        # AVAILABLE:: the package is available for this OS
        # IGNORE:: the package is available for this OS, but no packages need to
        #          be installed for it
        def availability_of(name)
            resolved = resolve_package(name)
            return NO_PACKAGE unless resolved

            if resolved.empty?
                if known_operating_system?
                    return WRONG_OS
                else
                    return UNKNOWN_OS
                end
            end

            resolved = resolved.find_all do |_, status, list|
                status != FOUND_PACKAGES || !list.empty?
            end
            failed = resolved.find_all do |_, status, _|
                status == FOUND_NONEXISTENT
            end
            if failed.empty?
                if resolved.empty?
                    return IGNORE
                else
                    return AVAILABLE
                end
            else
                return NONEXISTENT
            end
        end
    end
end
