require 'tempfile'
require 'json'

require 'autoproj/package_managers/manager'
require 'autoproj/package_managers/unknown_os_manager'
require 'autoproj/package_managers/shell_script_manager'

require 'autoproj/package_managers/apt_dpkg_manager'
require 'autoproj/package_managers/emerge_manager'
require 'autoproj/package_managers/homebrew_manager'
require 'autoproj/package_managers/pacman_manager'
require 'autoproj/package_managers/pkg_manager'
require 'autoproj/package_managers/port_manager'
require 'autoproj/package_managers/yum_manager'
require 'autoproj/package_managers/zypper_manager'

require 'autoproj/package_managers/gem_manager'
require 'autoproj/package_managers/pip_manager'

module Autoproj
    # Manager for packages provided by external package managers
    class OSDependencies
	class << self
	    # When requested to load a file called '$FILE', the osdeps code will
	    # also look for files called '$FILE-suffix', where 'suffix' is an
	    # element in +suffixes+
	    #
	    # A usage of this functionality is to make loading conditional to
	    # the available version of certain tools, namely Ruby. Autoproj for
	    # instance adds ruby18 when started on Ruby 1.8 and ruby19 when
	    # started on Ruby 1.9
	    attr_reader :suffixes
	end
	@suffixes = []

        def self.load(file)
	    if !File.file?(file)
		raise ArgumentError, "no such file or directory #{file}"
	    end

	    candidates = [file]
	    candidates.concat(suffixes.map { |s| "#{file}-#{s}" })

            error_t = if defined? Psych::SyntaxError then [ArgumentError, Psych::SyntaxError]
                      else ArgumentError
                      end

	    result = OSDependencies.new
	    candidates.each do |file|
                next if !File.file?(file)
                file = File.expand_path(file)
                begin
                    data = YAML.load(File.read(file)) || Hash.new
                    verify_definitions(data)
                rescue *error_t => e
                    raise ConfigError.new, "error in #{file}: #{e.message}", e.backtrace
                end

                result.merge(OSDependencies.new(data, file))
	    end
	    result
        end

        class << self
            attr_reader :aliases
            attr_accessor :force_osdeps
        end
        @aliases = Hash.new

        attr_writer :silent
        def silent?; @silent end

        def self.alias(old_name, new_name)
            @aliases[new_name] = old_name
        end

	def self.ruby_version_keyword
            "ruby#{RUBY_VERSION.split('.')[0, 2].join("")}"
        end

        def self.autodetect_ruby_program
            ruby = RbConfig::CONFIG['RUBY_INSTALL_NAME']
            ruby_bindir = RbConfig::CONFIG['bindir']
            ruby_executable = File.join(ruby_bindir, ruby)
            Autobuild.programs['ruby'] = ruby_executable
            ruby_executable
        end

        def self.autodetect_ruby
            self.alias(ruby_version_keyword, "ruby")
        end
	self.suffixes << ruby_version_keyword
        autodetect_ruby

        AUTOPROJ_OSDEPS = File.join(File.expand_path(File.dirname(__FILE__)), 'default.osdeps')
        def self.load_default
            file = ENV['AUTOPROJ_DEFAULT_OSDEPS'] || AUTOPROJ_OSDEPS
            if !File.file?(file)
                Autoproj.warn "#{file} (from AUTOPROJ_DEFAULT_OSDEPS) is not a file, falling back to #{AUTOPROJ_OSDEPS}"
                file = AUTOPROJ_OSDEPS
            end
            OSDependencies.load(file)
        end

        def load_default
            merge(self.class.load_default)
        end

        PACKAGE_HANDLERS = [PackageManagers::AptDpkgManager,
            PackageManagers::GemManager,
            PackageManagers::EmergeManager,
            PackageManagers::PacmanManager,
            PackageManagers::HomebrewManager,
            PackageManagers::YumManager,
            PackageManagers::PortManager,
            PackageManagers::ZypperManager,
            PackageManagers::PipManager ,
            PackageManagers::PkgManager]
        
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
        OS_PACKAGE_HANDLERS = {
            'debian' => 'apt-dpkg',
            'gentoo' => 'emerge',
            'arch' => 'pacman',
            'fedora' => 'yum',
            'macos-port' => 'macports',
            'macos-brew' => 'brew',
            'opensuse' => 'zypper',
            'freebsd' => 'pkg'
        }

        # The information contained in the OSdeps files, as a hash
        attr_reader :definitions
        # All the information contained in all the OSdeps files, as a mapping
        # from the OSdeps package name to [osdeps_file, definition] pairs
        attr_reader :all_definitions
        # The information as to from which osdeps file the current package
        # information in +definitions+ originates. It is a mapping from the
        # package name to the osdeps file' full path
        attr_reader :sources

        # Use to override the autodetected OS-specific package handler
        attr_writer :os_package_handler

        # Returns the package manager object for the current OS
        def os_package_handler
            if @os_package_handler.nil?
                os_names, _ = OSDependencies.operating_system
                if os_names && (key = os_names.find { |name| OS_PACKAGE_HANDLERS[name] })
                    @os_package_handler = package_handlers[OS_PACKAGE_HANDLERS[key]]
                    if !@os_package_handler
                        raise ArgumentError, "found #{OS_PACKAGE_HANDLERS[name]} as the required package handler for #{os_names.join(", ")}, but it is not registered"
                    end
                else
                    @os_package_handler = PackageManagers::UnknownOSManager.new
                end
            end
            return @os_package_handler
        end

        # Returns the set of package managers
        def package_handlers
            if !@package_handlers
                @package_handlers = Hash.new
                PACKAGE_HANDLERS.each do |klass|
                    obj = klass.new
                    obj.names.each do |n|
                        @package_handlers[n] = obj
                    end
                end
            end
            @package_handlers
        end

        # The Gem::SpecFetcher object that should be used to query RubyGems, and
        # install RubyGems packages
        def initialize(defs = Hash.new, file = nil)
            @definitions = defs.to_hash
            @all_definitions = Hash.new { |h, k| h[k] = Array.new }

            @sources     = Hash.new
            @installed_packages = Set.new
            if file
                defs.each_key do |package_name|
                    sources[package_name] = file
                    all_definitions[package_name] << [[file], defs[package_name]]
                end
            end
            @silent = true
            @filter_uptodate_packages = true
        end

        # Returns the name of all known OS packages
        #
        # It includes even the packages for which there are no definitions on
        # this OS
        def all_package_names
            all_definitions.keys
        end

        # Returns the full path to the osdeps file from which the package
        # definition for +package_name+ has been taken
        def source_of(package_name)
            sources[package_name]
        end

        # Merges the osdeps information of +info+ into +self+. If packages are
        # defined in both OSDependencies objects, the information in +info+
        # takes precedence
        def merge(info)
            root_dir = nil
            @definitions = definitions.merge(info.definitions) do |h, v1, v2|
                if v1 != v2
                    root_dir ||= "#{Autoproj.root_dir}/"
                    old = source_of(h).gsub(root_dir, '')
                    new = info.source_of(h).gsub(root_dir, '')

                    # Warn if the new osdep definition resolves to a different
                    # set of packages than the old one
                    old_resolved = resolve_package(h).inject(Hash.new) do |osdep_h, (handler, status, list)|
                        osdep_h[handler.name] = [status, list]
                        osdep_h
                    end
                    new_resolved = info.resolve_package(h).inject(Hash.new) do |osdep_h, (handler, status, list)|
                        osdep_h[handler.name] = [status, list]
                        osdep_h
                    end
                    if old_resolved != new_resolved
                        Autoproj.warn("osdeps definition for #{h}, previously defined in #{old} overridden by #{new}")
                    end
                end
                v2
            end
            @sources = sources.merge(info.sources)
            @all_definitions = all_definitions.merge(info.all_definitions) do |package_name, all_defs, new_all_defs|
                all_defs = all_defs.dup
                new_all_defs = new_all_defs.dup
                new_all_defs.delete_if do |files, data|
                    if entry = all_defs.find { |_, d| d == data }
                        entry[0] |= files
                    end
                end
                all_defs.concat(new_all_defs)
            end
        end

        # Perform some sanity checks on the given osdeps definitions
        def self.verify_definitions(hash, path = [])
            hash.each do |key, value|
                if value && !key.kind_of?(String)
                    raise ArgumentError, "invalid osdeps definition: found an #{key.class} as a key in #{path.join("/")}. Don't forget to put quotes around numbers"
                elsif !value && (key.kind_of?(Hash) || key.kind_of?(Array))
                    verify_definitions(key)
                end
                next if !value

                if value.kind_of?(Array) || value.kind_of?(Hash)
                    verify_definitions(value, (path + [key]))
                else
                    if !value.kind_of?(String)
                        raise ArgumentError, "invalid osdeps definition: found an #{value.class} as a value in #{path.join("/")}. Don't forget to put quotes around numbers"
                    end
                end
            end
        end

        # Returns true if it is possible to install packages for the operating
        # system on which we are installed
        def self.supported_operating_system?
            if @supported_operating_system.nil?
                os_names, _ = operating_system
                @supported_operating_system =
                    if !os_names then false
                    else
                        os_names.any? { |os_name| OS_PACKAGE_HANDLERS.has_key?(os_name) }
                    end
            end
            return @supported_operating_system
        end

        # Used mainly during testing to bypass the operating system
        # autodetection
        def self.operating_system=(values)
            @supported_operating_system = nil
            @operating_system = values
        end

        def self.guess_operating_system
            if File.exists?('/etc/debian_version')
                versions = [File.read('/etc/debian_version').strip]
                if versions.first =~ /sid/
                    versions = ["unstable", "sid"]
                end
                [['debian'], versions]
            elsif File.exists?('/etc/redhat-release')
                release_string = File.read('/etc/redhat-release').strip
                release_string =~ /(.*) release ([\d.]+)/
                name = $1.downcase
                version = $2
                if name =~ /Red Hat Entreprise/
                    name = 'rhel'
                end
                [[name], [version]]
            elsif File.exists?('/etc/gentoo-release')
                release_string = File.read('/etc/gentoo-release').strip
                release_string =~ /^.*([^\s]+)$/
                version = $1
                [['gentoo'], [version]]
            elsif File.exists?('/etc/arch-release')
                [['arch'], []]
            elsif Autobuild.macos? 
                version=`sw_vers | head -2 | tail -1`.split(":")[1]
                manager =
                    if ENV['AUTOPROJ_MACOSX_PACKAGE_MANAGER']
                        ENV['AUTOPROJ_MACOSX_PACKAGE_MANAGER']
                    else 'macos-brew'
                    end
                if !OS_PACKAGE_HANDLERS.include?(manager)
                    known_managers = OS_PACKAGE_HANDLERS.keys.grep(/^macos/)
                    raise ArgumentError, "#{manager} is not a known MacOSX package manager. Known package managers are #{known_managers.join(", ")}"
                end

                managers = 
                    if manager == 'macos-port'
                        [manager, 'port']
                    else [manager]
                    end
                [[*managers, 'darwin'], [version.strip]]
            elsif Autobuild.windows?
                [['windows'], []]
            elsif File.exists?('/etc/SuSE-release')
                version = File.read('/etc/SuSE-release').strip
                version =~/.*VERSION\s+=\s+([^\s]+)/
                version = $1
                [['opensuse'], [version.strip]]
            elsif Autobuild.freebsd? 
		version = `uname -r`.strip.split("-")[0]
		[['freebsd'],[version]]
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
                if File.exists?(file) && !names.include?(name)
                    names << name
                end
            end
            names
        end
        
        def self.normalize_os_representation(names, versions)
            # Normalize the names to lowercase
            names    = names.map(&:downcase)
            versions = versions.map(&:downcase)
            if !versions.include?('default')
                versions += ['default']
            end
            return names, versions
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
        def self.operating_system(options = Hash.new)
            # Validate the options. We check on the availability of
            # validate_options as to not break autoproj_bootstrap (in which
            # validate_options is not available)
            options = validate_options options, force: false, config: Autoproj.config
            config  = options.fetch(:config)

            if user_os = ENV['AUTOPROJ_OS']
                @operating_system =
                    if user_os.empty? then false
                    else
                        names, versions = user_os.split(':')
                        normalize_os_representation(names.split(','), versions.split(','))
                    end
                return @operating_system
            end


            if options[:force]
                @operating_system = nil
            elsif !@operating_system.nil? # @operating_system can be set to false to simulate an unknown OS
                return @operating_system
            elsif config.has_value_for?('operating_system')
                os = config.get('operating_system')
                if os.respond_to?(:to_ary)
                    if os[0].respond_to?(:to_ary) && os[0].all? { |s| s.respond_to?(:to_str) } &&
                       os[1].respond_to?(:to_ary) && os[1].all? { |s| s.respond_to?(:to_str) }
                       @operating_system = os
                       return os
                    end
                end
                @operating_system = nil # Invalid OS format in the configuration file
            end

            Autobuild.progress :operating_system_autodetection, "autodetecting the operating system"
            names, versions = os_from_os_release

            if !names
                names, versions = guess_operating_system
            end

            # on Debian, they refuse to put enough information to detect
            # 'unstable' reliably. So, we use the heuristic method for it
            if names[0] == "debian"
                # check if we actually got a debian with the "unstable" (sid)
                # flavour. it seems that "/etc/debian_version" does not contain
                # "sid" (but "8.0" for example) during the feature freeze
                # phase...
                if File.exists?('/etc/debian_version')
                    debian_versions = [File.read('/etc/debian_version').strip]
                    if debian_versions.first =~ /sid/
                        versions = ["unstable", "sid"]
                    end
                end
                # otherwise "versions" contains the result it previously had
            end
            return if !names

            names = ensure_derivatives_refer_to_their_parents(names)
            names, versions = normalize_os_representation(names, versions)

            @operating_system = [names, versions]
            config.set('operating_system', @operating_system, true)
            Autobuild.progress :operating_system_autodetection, "operating system: #{(names - ['default']).join(",")} - #{(versions - ['default']).join(",")}"
            @operating_system
        ensure
            Autobuild.progress_done :operating_system_autodetection
        end

        def self.os_from_os_release(filename = '/etc/os-release')
            return if !File.exists?(filename)

            fields = Hash.new
            File.readlines(filename).each do |line|
                line = line.strip
                if line.strip =~ /^(\w+)=(?:["'])?([^"']+)(?:["'])?$/
                    fields[$1] = $2
                elsif !line.empty?
                    Autoproj.warn "could not parse line '#{line.inspect}' in /etc/os-release"
                end
            end

            names = []
            versions = []
            names << fields['ID'] << fields['ID_LIKE']
            versions << fields['VERSION_ID']
            version = fields['VERSION'] || ''
            versions.concat(version.gsub(/[^\w.]/, ' ').split(' '))
            return names.compact.uniq, versions.compact.uniq
        end

        def self.os_from_lsb
            if !Autobuild.find_in_path('lsb_release')
                return
            end

            distributor = [`lsb_release -i -s`.strip.downcase]
            codename    = `lsb_release -c -s`.strip.downcase
            version     = `lsb_release -r -s`.strip.downcase

            return [distributor, [codename, version]]
        end

        class InvalidRecursiveStatement < Autobuild::Exception; end

        # Return the path to the osdeps name for a given package name while
        # accounting for package aliases
        #
        # returns an array contain the path starting with name and
        # ending at the resolved name
        def self.resolve_name(name)
            path = [ name ]
            while OSDependencies.aliases.has_key?(name)
                name = OSDependencies.aliases[name]
                path << name
            end
            path
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
        def resolve_package(name)
            path = OSDependencies.resolve_name(name)
            name = path.last

            os_names, os_versions = OSDependencies.operating_system
            os_names = os_names.dup
            os_names << 'default'

            dep_def = definitions[name]
            if !dep_def
                return nil
            end

            # Partition the found definition in all entries that are interesting
            # for us: toplevel os-independent package managers, os-dependent
            # package managers and os-independent package managers selected by
            # OS or version
            if !os_names
                os_names = ['default']
                os_versions = ['default']
            end

            package_handler_names = package_handlers.keys

            result = []
            found, pkg = partition_osdep_entry(name, dep_def, nil, (package_handler_names - os_package_handler.names), os_names, os_versions)
            if found
                result << [os_package_handler, found, pkg]
            end

            # NOTE: package_handlers might contain the same handler multiple
            # times (when a package manager has multiple names). That's why we
            # do a to_set.each
            package_handlers.each_value.to_set.each do |handler|
                found, pkg = partition_osdep_entry(name, dep_def, handler.names, [], os_names, os_versions)
                if found
                    result << [handler, found, pkg]
                end
            end

            # Recursive resolutions
            found, pkg = partition_osdep_entry(name, dep_def, ['osdep'], [], os_names, os_versions)
            if found
                pkg.each do |pkg_name|
                    resolved = resolve_package(pkg_name)
                    if !resolved
                        raise InvalidRecursiveStatement, "osdep #{pkg_name} does not exist. It is referred to by #{name}."
                    end
                    result.concat(resolved)
                end
            end

            result.map do |handler, status, entries|
                if handler.respond_to?(:parse_package_entry)
                    [handler, status, entries.map { |s| handler.parse_package_entry(s) }]
                else
                    [handler, status, entries]
                end
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
                    # Raw array of packages. Possible only if we are not at toplevel
                    # (i.e. if we already have a handler)
                    if names == 'ignore'
                        found = true if !handler_names
                    elsif names == 'nonexistent'
                        nonexistent = true if !handler_names
                    elsif !handler_names && names.kind_of?(Array)
                        result.concat(result)
                        found = true
                    elsif names.respond_to?(:to_str)
                        if excluded.include?(names)
                        elsif handler_names && handler_names.include?(names)
                            result << osdep_name
                            found = true
                        elsif !handler_names
                            result << names
                            found = true
                        end
                    elsif names.respond_to?(:to_hash)
                        rec_found, rec_result = partition_osdep_entry(osdep_name, names, handler_names, excluded, keys, *additional_keys)
                        if rec_found == FOUND_NONEXISTENT then nonexistent = true
                        elsif rec_found == FOUND_PACKAGES then found = true
                        end
                        result.concat(rec_result)
                    end
                else
                    if names.respond_to?(:to_str) # names could be an array already
                        names = names.split(',')
                    end

                    if handler_names
                        if matching_name = handler_names.find { |k| names.any? { |name_tag| k == name_tag.downcase } }
                            rec_found, rec_result = partition_osdep_entry(osdep_name, values, nil, excluded, keys, *additional_keys)
                            if rec_found == FOUND_NONEXISTENT then nonexistent = true
                            elsif rec_found == FOUND_PACKAGES then found = true
                            end
                            result.concat(rec_result)
                        end
                    end

                    matching_name = keys.find { |k| names.any? { |name_tag| k == name_tag.downcase } }
                    if matching_name
                        rec_found, rec_result = partition_osdep_entry(osdep_name, values, handler_names, excluded, *additional_keys)
                        # We only consider the first highest-priority entry,
                        # regardless of whether it has some packages for us or
                        # not
                        idx = keys.index(matching_name)
                        if !rec_found
                            if !found_keys.has_key?(idx)
                                found_keys[idx] = nil
                            end
                        else
                            found_keys[idx] ||= [0, []]
                            found_keys[idx][0] += rec_found
                            found_keys[idx][1].concat(rec_result)
                        end
                    end
                end
            end
            first_entry = found_keys.keys.sort.first
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

            return found, result
        end

        # Resolves the given OS dependencies into the actual packages that need
        # to be installed on this particular OS.
        #
        # @param [Array<String>] dependencies the list of osdep names that should be resolved
        # @return [Array<#install,Array<String>>] the set of packages, grouped
        #   by the package handlers that should be used to install them
        #
        # @raise MissingOSDep if some packages can't be found or if the
        #   nonexistent keyword was found for some of them
        def resolve_os_dependencies(dependencies)
            all_packages = []
            dependencies.each do |name|
                result = resolve_package(name)
                if !result
                    path = OSDependencies.resolve_name(name)
                    raise MissingOSDep.new, "there is no osdeps definition for #{path.last} (search tree: #{path.join("->")})"
                end

                if result.empty?
                    if OSDependencies.supported_operating_system?
                        os_names, os_versions = OSDependencies.operating_system
                        raise MissingOSDep.new, "there is an osdeps definition for #{name}, but not for this operating system and version (resp. #{os_names.join(", ")} and #{os_versions.join(", ")})"
                    end
                    result = [[os_package_handler, FOUND_PACKAGES, [name]]]
                end

                result.each do |handler, status, packages|
                    if status == FOUND_NONEXISTENT
                        raise MissingOSDep.new, "there is an osdep definition for #{name}, and it explicitely states that this package does not exist on your OS"
                    end
                    if entry = all_packages.find { |h, _| h == handler }
                        entry[1].concat(packages)
                    else
                        all_packages << [handler, packages]
                    end
                end
            end

            all_packages.delete_if do |handler, pkg|
                pkg.empty?
            end
            return all_packages
        end


        # Returns true if +name+ is an acceptable OS package for this OS and
        # version
        def has?(name)
            status = availability_of(name)
            status == AVAILABLE || status == IGNORE
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
            if !resolved
                return NO_PACKAGE
            end

            if resolved.empty?
                if !OSDependencies.operating_system
                    return UNKNOWN_OS
                elsif !OSDependencies.supported_operating_system?
                    return AVAILABLE
                else return WRONG_OS
                end
            end

            resolved = resolved.delete_if { |_, status, list| status == FOUND_PACKAGES && list.empty? }
            failed = resolved.find_all do |handler, status, list|
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

        HANDLE_ALL  = 'all'
        HANDLE_RUBY = 'ruby'
        HANDLE_OS   = 'os'
        HANDLE_NONE = 'none'

        def self.osdeps_mode_option_unsupported_os(config = Autoproj.config)
            long_doc =<<-EOT
The software packages that autoproj will have to build may require other
prepackaged softwares (a.k.a. OS dependencies) to be installed (RubyGems
packages, packages from your operating system/distribution, ...). Autoproj is
usually able to install those automatically, but unfortunately your operating
system is not (yet) supported by autoproj's osdeps mechanism, it can only offer
you some limited support.

Some package handlers are cross-platform, and are therefore supported.  However,
you will have to install the kind of OS dependencies (so-called OS packages)

This option is meant to allow you to control autoproj's behaviour while handling
OS dependencies.

* if you say "all", all OS-independent packages are going to be installed.
* if you say "gem", the RubyGem packages will be installed.
* if you say "pip", the Pythin PIP packages will be installed.
* if you say "none", autoproj will not do anything related to the OS
  dependencies.

As any configuration value, the mode can be changed anytime by calling
  autoproj reconfigure

Finally, the "autoproj osdeps" command will give you the necessary information
about the OS packages that you will need to install manually.

So, what do you want ? (all, none or a comma-separated list of: gem pip)
            EOT
            message = [ "Which prepackaged software (a.k.a. 'osdeps') should autoproj install automatically (all, none or a comma-separated list of: gem pip) ?", long_doc.strip ]

	    config.declare 'osdeps_mode', 'string',
		:default => 'ruby',
		:doc => message,
                :lowercase => true
        end

        def self.osdeps_mode_option_supported_os(config = Autoproj.config)
            long_doc =<<-EOT
The software packages that autoproj will have to build may require other
prepackaged softwares (a.k.a. OS dependencies) to be installed (RubyGems
packages, packages from your operating system/distribution, ...). Autoproj
is able to install those automatically for you.

Advanced users may want to control this behaviour. Additionally, the
installation of some packages require administration rights, which you may
not have. This option is meant to allow you to control autoproj's behaviour
while handling OS dependencies.

* if you say "all", it will install all packages automatically.
  This requires root access thru 'sudo'
* if you say "pip", only the Ruby packages will be installed.
  Installing these packages does not require root access.
* if you say "gem", only the Ruby packages will be installed.
  Installing these packages does not require root access.
* if you say "os", only the OS-provided packages will be installed.
  Installing these packages requires root access.
* if you say "none", autoproj will not do anything related to the
  OS dependencies.

Finally, you can provide a comma-separated list of pip gem and os.

As any configuration value, the mode can be changed anytime by calling
  autoproj reconfigure

Finally, the "autoproj osdeps" command will give you the necessary information
about the OS packages that you will need to install manually.

So, what do you want ? (all, none or a comma-separated list of: os gem pip)
            EOT
            message = [ "Which prepackaged software (a.k.a. 'osdeps') should autoproj install automatically (all, none or a comma-separated list of: os gem pip) ?", long_doc.strip ]

	    config.declare 'osdeps_mode', 'string',
		:default => 'all',
		:doc => message,
                :lowercase => true
        end

        def self.define_osdeps_mode_option(config = Autoproj.config)
            if supported_operating_system?
                osdeps_mode_option_supported_os(config)
            else
                osdeps_mode_option_unsupported_os(config)
            end
        end

        def self.osdeps_mode_string_to_value(string)
            string = string.to_s.downcase.split(',')
            modes = []
            string.map do |str|
                case str
                when 'all'  then modes.concat(['os', 'gem', 'pip'])
                when 'ruby' then modes << 'gem'
                when 'gem'  then modes << 'gem'
                when 'pip'  then modes << 'pip'
                when 'os'   then modes << 'os'
                when 'none' then
                else raise ArgumentError, "#{str} is not a known package handler"
                end
            end
            modes
        end

        # If set to true (the default), #install will try to remove the list of
        # already uptodate packages from the installed packages. Set to false to
        # install all packages regardless of their status
        attr_writer :filter_uptodate_packages

        # If set to true (the default), #install will try to remove the list of
        # already uptodate packages from the installed packages. Use
        # #filter_uptodate_packages= to set it to false to install all packages
        # regardless of their status
        def filter_uptodate_packages?
            !!@filter_uptodate_packages
        end

        # Override the osdeps mode
        def osdeps_mode=(value)
            @osdeps_mode = OSDependencies.osdeps_mode_string_to_value(value)
        end

        # Returns the osdeps mode chosen by the user
        def osdeps_mode
            # This has two uses. It caches the value extracted from the
            # AUTOPROJ_OSDEPS_MODE and/or configuration file. Moreover, it
            # allows to override the osdeps mode by using
            # OSDependencies#osdeps_mode=
            if @osdeps_mode
                return @osdeps_mode
            end

            @osdeps_mode = OSDependencies.osdeps_mode
        end

        def self.osdeps_mode(config = Autoproj.config)
            while true
                mode =
                    if !config.has_value_for?('osdeps_mode') &&
                        mode_name = ENV['AUTOPROJ_OSDEPS_MODE']
                        begin OSDependencies.osdeps_mode_string_to_value(mode_name)
                        rescue ArgumentError
                            Autoproj.warn "invalid osdeps mode given through AUTOPROJ_OSDEPS_MODE (#{mode})"
                            nil
                        end
                    else
                        mode_name = config.get('osdeps_mode')
                        begin OSDependencies.osdeps_mode_string_to_value(mode_name)
                        rescue ArgumentError
                            Autoproj.warn "invalid osdeps mode stored in configuration file"
                            nil
                        end
                    end

                if mode
                    @osdeps_mode = mode
                    config.set('osdeps_mode', mode_name, true)
                    return mode
                end

                # Invalid configuration values. Retry
                config.reset('osdeps_mode')
                ENV['AUTOPROJ_OSDEPS_MODE'] = nil
            end
        end

        # The set of packages that have already been installed
        attr_reader :installed_packages

        # Set up the registered package handlers according to the specified osdeps mode
        #
        # It enables/disables package handlers based on either the value
        # returned by {#osdeps_mode} or the value passed as option (the latter
        # takes precedence). Moreover, sets the handler's silent flag using
        # {#silent?}
        #
        # @option options [Array<String>] the package handlers that should be
        #   enabled. The default value is returned by {#osdeps_mode}
        # @return [Array<PackageManagers::Manager>] the set of enabled package
        #   managers
        def setup_package_handlers(options = Hash.new)
            options =
                if Kernel.respond_to?(:validate_options)
                    Kernel.validate_options options,
                        osdeps_mode: osdeps_mode
                else
                    options = options.dup
                    options[:osdeps_mode] ||= osdeps_mode
                    options
                end

            os_package_handler.enabled = false
            package_handlers.each_value do |handler|
                handler.enabled = false
            end
            options[:osdeps_mode].each do |m|
                if m == 'os'
                    os_package_handler.enabled = true
                elsif pkg = package_handlers[m]
                    pkg.enabled = true
                else
                    Autoproj.warn "osdep handler #{m.inspect} has no handler, available handlers are #{package_handlers.keys.map(&:inspect).sort.join(", ")}"
                end
            end
            os_package_handler.silent = self.silent?
            package_handlers.each_value do |v|
                v.silent = self.silent?
            end

            enabled_handlers = []
            if os_package_handler.enabled?
                enabled_handlers << os_package_handler
            end
            package_handlers.each_value do |v|
                if v.enabled?
                    enabled_handlers << v
                end
            end
            enabled_handlers
        end

        # Requests that packages that are handled within the autoproj project
        # (i.e. gems) are restored to pristine condition
        #
        # This is usually called as a rebuild step to make sure that all these
        # packages are updated to whatever required the rebuild
        def pristine(packages, options = Hash.new)
            install(packages, options.merge(install_only: true))
            packages = resolve_os_dependencies(packages)

            _, other_packages =
                packages.partition { |handler, list| handler == os_package_handler }
            other_packages.each do |handler, list|
                if handler.respond_to?(:pristine)
                    handler.pristine(list)
                end
            end
        end

        # Requests the installation of the given set of packages
        def install(packages, options = Hash.new)
            # Remove the set of packages that have already been installed 
            packages = packages.to_set - installed_packages
            return false if packages.empty?

            filter_options, options =
                filter_options options, install_only: !Autobuild.do_update
            setup_package_handlers(options)

            packages = resolve_os_dependencies(packages)

            needs_filter = (filter_uptodate_packages? || filter_options[:install_only])
            packages = packages.map do |handler, list|
                if needs_filter && handler.respond_to?(:filter_uptodate_packages)
                    list = handler.filter_uptodate_packages(list, filter_options)
                end

                if !list.empty?
                    [handler, list]
                end
            end.compact
            return false if packages.empty?

            # Install OS packages first, as the other package handlers might
            # depend on OS packages
            os_packages, other_packages = packages.partition { |handler, list| handler == os_package_handler }
            [os_packages, other_packages].each do |packages|
                packages.each do |handler, list|
                    handler.install(list)
                    @installed_packages |= list.to_set
                end
            end
            true
        end

        def reinstall(options = Hash.new)
            # We also reinstall the osdeps that provide the
            # functionality
            managers = setup_package_handlers(options)
            managers.each do |mng|
                if mng.enabled? && mng.respond_to?(:reinstall)
                    mng.reinstall
                end
            end
        end
    end
end

