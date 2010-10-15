require 'highline'
require 'utilrb/module/attr_predicate'
module Autoproj
    class << self
        attr_accessor :verbose
        attr_reader :console
        attr_predicate :silent?, true
    end
    @silent  = false
    @verbose = false
    @console = HighLine.new

    def self.progress(*args)
        if !silent?
            if args.empty?
                puts
            else
                STDERR.puts console.color(*args)
            end
        end
    end

    def self.color(*args)
        console.color(*args)
    end

    # Displays a warning message
    def self.warn(message)
        Autoproj.progress("  WARN: #{message}", :magenta)
    end

    module CmdLine
	def self.handle_automatic_osdeps
            if !Autoproj.has_config_key?('automatic_osdeps') && ENV['AUTOPROJ_AUTOMATIC_OSDEPS']
                mode = ENV['AUTOPROJ_AUTOMATIC_OSDEPS']
                mode =
                    if mode == 'true'     then Autoproj::OSDependencies::AUTOMATIC
                    elsif mode == 'false' then Autoproj::OSDependencies::MANUAL
                    elsif mode == 'wait'  then Autoproj::OSDependencies::WAIT
                    else Autoproj::OSDependencies::ASK
                    end

                Autoproj.change_option('automatic_osdeps', mode, true)
            end

            short_doc = "Should autoproj handle the OS package installation automatically (yes, no, wait or ask) ?"
            long_doc =<<-EOT
* if you say "yes", the OS dependencies will be handled by autoproj.
* if you say "no", the list of OS dependencies that need to be installed
  will be listed, and autoproj will go on, assuming that you have installed them yourself.
* if you say "ask", you will be prompted each time a package needs to be installed.
* if you say "wait", autoproj will simply wait for you to press ENTER to
  continue after it prompted you for the dependencies.
    
This value can be changed anytime by calling an autoproj operation
with the --reconfigure option (e.g. autoproj update --reconfigure).
Moreover, the "autoproj osdeps" call will always allow you to install
OS dependencies through autoproj.
            EOT
            long_doc = long_doc.strip

	    Autoproj.configuration_option 'automatic_osdeps', 'string',
		:default => 'yes',
		:doc => [short_doc, long_doc] do |value|
                    begin
                        Autoproj::BuildOption.validate_boolean(value, Hash.new)
                    rescue Autoproj::InputError
                        if value.to_s == "ask"
                            :ask
                        elsif value.to_s == "wait"
                            :wait
                        else
                            raise Autoproj::InputError, "invalid value. Please answer 'yes', 'no', 'wait' or 'ask' -- without the quotes"
                        end
                    end
                end

	    Autoproj.user_config('automatic_osdeps')
	end

        def self.initialize
            Autobuild::Reporting << Autoproj::Reporter.new
            if mail_config[:to]
                Autobuild::Reporting << Autobuild::MailReporter.new(mail_config)
            end

            Autoproj.load_config

            if Autoproj.has_config_key?('prefix')
                Autoproj.prefix = Autoproj.user_config('prefix')
            end

            # If we are under rubygems, check that the GEM_HOME is right ...
            if $LOADED_FEATURES.any? { |l| l =~ /rubygems/ }
                if ENV['GEM_HOME'] != Autoproj.gem_home
                    raise ConfigError, "RubyGems is already loaded with a different GEM_HOME, make sure you are loading the right env.sh script !"
                end
            end

            # Set up some important autobuild parameters
            Autoproj.env_inherit 'PATH', 'PKG_CONFIG_PATH', 'RUBYLIB', 'LD_LIBRARY_PATH'
            Autoproj.env_set 'GEM_HOME', Autoproj.gem_home
            Autoproj.env_add 'PATH', File.join(Autoproj.gem_home, 'bin')
            Autoproj.env_set 'RUBYOPT', "-rubygems"
            Autobuild.prefix  = Autoproj.build_dir
            Autobuild.srcdir  = Autoproj.root_dir
            Autobuild.logdir = File.join(Autobuild.prefix, 'log')

	    handle_automatic_osdeps

            ruby = RbConfig::CONFIG['RUBY_INSTALL_NAME']
            if ruby != 'ruby'
                bindir = File.join(Autoproj.build_dir, 'bin')
                FileUtils.mkdir_p bindir
                File.open(File.join(bindir, 'ruby'), 'w') do |io|
                    io.puts "#! /bin/sh"
                    io.puts "exec #{ruby} \"$@\""
                end
                FileUtils.chmod 0755, File.join(bindir, 'ruby')

                Autoproj.env_add 'PATH', bindir
            end

            # We load the local init.rb first so that the manifest loading
            # process can use options defined there for the autoproj version
            # control information (for instance)
            local_source = LocalSource.new
            Autoproj.load_if_present(local_source, local_source.local_dir, "init.rb")

            manifest_path = File.join(Autoproj.config_dir, 'manifest')
            Autoproj.manifest = Manifest.load(manifest_path)

            # Once thing left to do: handle the Autoproj.auto_update
            # configuration parameter. This has to be done here as the rest of
            # the configuration update/loading procedure rely on it.
            #
            # Namely, we must check if Autobuild.do_update has been explicitely
            # set to true or false. If that is the case, don't do anything.
            # Otherwise, set it to the value of auto_update (set in the
            # manifest)
            if Autobuild.do_update.nil?
                Autobuild.do_update = manifest.auto_update?
            end
            if Autoproj::CmdLine.update_os_dependencies.nil?
                Autoproj::CmdLine.update_os_dependencies = manifest.auto_osdeps?
            end

            # Initialize the Autoproj.osdeps object by loading the default. The
            # rest is loaded later
            Autoproj.osdeps = Autoproj::OSDependencies.load_default
        end

        def self.update_myself
            return if !Autoproj::CmdLine.update_os_dependencies?

            # First things first, see if we need to update ourselves
            if Autoproj.osdeps.install(%w{autobuild autoproj})
                # We updated autobuild or autoproj themselves ... Restart !
                #
                # ...But first save the configuration (!)
                Autoproj.save_config
                require 'rbconfig'
                ruby = RbConfig::CONFIG['RUBY_INSTALL_NAME']
                exec(ruby, $0, *ARGV)
            end
        end

        def self.load_configuration(silent = false)
            manifest = Autoproj.manifest

            # Load init.rb files. each_source must not load the source.yml file, as
            # init.rb may define configuration options that are used there
            manifest.each_source(false) do |source|
                Autoproj.load_if_present(source, source.local_dir, "init.rb")
            end

            # Load the required autobuild definitions
            if !silent
                Autoproj.progress("autoproj: loading ...", :bold)
                if !Autoproj.reconfigure?
                    Autoproj.progress("run 'autoproj --reconfigure' to change configuration values", :bold)
                end
            end
            manifest.each_autobuild_file do |source, name|
                Autoproj.import_autobuild_file source, name
            end

            # Now, load the package's importer configurations (from the various
            # source.yml files)
            manifest.load_importers

            # We finished loading the configuration files. Not all configuration
            # is done (since we need to process the package setup blocks), but
            # save the current state of the configuration anyway.
            Autoproj.save_config

            # Loads OS package definitions once and for all
            Autoproj.load_osdeps_from_package_sets
        end

        def self.update_configuration
            manifest = Autoproj.manifest

            # Load the installation's manifest a first time, to check if we should
            # update it ... We assume that the OS dependencies for this VCS is already
            # installed (i.e. that the user did not remove it)
            if manifest.vcs
                manifest.update_yourself
                manifest_path = File.join(Autoproj.config_dir, 'manifest')
                Autoproj.manifest = manifest = Manifest.load(manifest_path)
            end

            source_os_dependencies = manifest.each_remote_source(false).
                inject(Set.new) do |set, source|
                    set << source.vcs.type if !source.local?
                end

            # Update the remote sources if there are any
            if manifest.has_remote_sources?
                Autoproj.progress("autoproj: updating remote definitions of package sets", :bold)
                # If we need to install some packages to import our remote sources, do it
                if update_os_dependencies?
                    Autoproj.osdeps.install(source_os_dependencies)
                end

                manifest.update_remote_sources
                Autoproj.progress
            end
        end

        def self.initial_package_setup
            manifest = Autoproj.manifest

            # Now starts a different stage of the whole build. Until now, we were
            # working on the whole package set. Starting from now, we need to build the
            # package sets based on the layout file
            #
            # First, we allow to user to specify packages based on disk paths, so
            # resolve those
            seen = Set.new
            manifest.each_package_set do |name, packages, enabled_packages|
                packages -= seen

                srcdir  = File.join(Autoproj.root_dir, name)
                prefix  = File.join(Autoproj.build_dir, name)
                logdir  = File.join(prefix, "log")
                packages.each do |pkg_name|
                    pkg = Autobuild::Package[pkg_name]
                    pkg.srcdir = File.join(srcdir, pkg_name)
                    pkg.prefix = prefix
                    pkg.doc_target_dir = File.join(Autoproj.build_dir, 'doc', name, pkg_name)
                    pkg.logdir = logdir
                end
                seen |= packages
            end

            # Now call the blocks that the user defined in the autobuild files. We do it
            # now so that the various package directories are properly setup
            manifest.packages.each_value do |pkg|
                if pkg.user_block
                    pkg.user_block[pkg.autobuild]
                end
            end

            # Load the package's override files. each_source must not load the
            # source.yml file, as init.rb may define configuration options that are used
            # there
            manifest.each_source(false).to_a.reverse.each do |source|
                Autoproj.load_if_present(source, source.local_dir, "overrides.rb")
            end

            # We now have processed the process setup blocks. All configuration
            # should be done and we can save the configuration data.
            Autoproj.save_config
        end


        def self.display_sources(manifest)
            # We can't have the Manifest class load the source.yml file, as it
            # cannot resolve all constants. So we need to do it ourselves to get
            # the name ...
            sources = manifest.each_source(false).to_a

            if sources.empty?
                Autoproj.progress("autoproj: no package sets defined in autoproj/manifest", :bold, :red)
            else
                Autoproj.progress("autoproj: available package sets", :bold)
                manifest.each_source(false) do |source|
                    source_yml = source.raw_description_file
                    Autoproj.progress "  #{source_yml['name']}"
                    if source.local?
                        Autoproj.progress "    local source in #{source.local_dir}"
                    else
                        Autoproj.progress "    from:  #{source.vcs}"
                        Autoproj.progress "    local: #{source.local_dir}"
                    end

                    lines = []
                    source.each_package.
                        map { |pkg| [pkg.name, manifest.package_manifests[pkg.name]] }.
                        sort_by { |name, _| name }.
                        each do |name, source_manifest|
                            vcs_def = manifest.importer_definition_for(name)
                            if source_manifest
                                lines << [name, source_manifest.short_documentation]
                                lines << ["", vcs_def.to_s]
                            else
                                lines << [name, vcs_def.to_s]
                            end
                        end

                    w_col1, w_col2 = nil
                    lines.each do |col1, col2|
                        w_col1 = col1.size if !w_col1 || col1.size > w_col1
                        w_col2 = col2.size if !w_col2 || col2.size > w_col2
                    end
                    puts "    packages:"
                    format = "    | %-#{w_col1}s | %-#{w_col2}s |"
                    lines.each do |col1, col2|
                        puts(format % [col1, col2])
                    end
                end
            end
        end

        # Returns the set of packages that are actually selected based on what
        # the user gave on the command line
        def self.resolve_user_selection(selected_packages)
            manifest = Autoproj.manifest

            if selected_packages.empty?
                return manifest.default_packages
            end
            if selected_packages.empty? # no packages, terminate
                Autoproj.progress
                Autoproj.progress("autoproj: no packages defined", :red)
                exit 0
            end
            selected_packages = selected_packages.to_set

            selected_packages = manifest.expand_package_selection(selected_packages)
            if selected_packages.empty?
                Autoproj.progress("autoproj: wrong package selection on command line", :red)
                exit 1
            elsif Autoproj.verbose
                Autoproj.progress "will install #{selected_packages.to_a.join(", ")}"
            end
            selected_packages
        end

        def self.verify_package_availability(pkg_name)
            if reason = Autoproj.manifest.exclusion_reason(pkg_name)
                raise ConfigError, "#{pkg_name} is excluded from the build: #{reason}"
            end
            pkg = Autobuild::Package[pkg_name]
            if !pkg
                raise ConfigError, "#{pkg_name} does not seem to exist"
            end

            # Verify that its dependencies are there, and add
            # them to the selected_packages set so that they get
            # imported as well
            pkg.dependencies.each do |dep_name|
                begin
                    verify_package_availability(dep_name)
                rescue ConfigError => e
                    raise e, "#{pkg_name} depends on #{dep_name}, but #{e.message}"
                end
            end
        end

        def self.import_packages(selected_packages)
            selected_packages = selected_packages.dup.
                map do |pkg_name|
                    pkg = Autobuild::Package[pkg_name]
                    if !pkg
                        raise ConfigError, "selected package #{pkg_name} does not exist"
                    end
                    pkg
                end.to_set

            # First, import all packages that are already there to make
            # automatic dependency discovery possible
            old_update_flag = Autobuild.do_update
            begin
                Autobuild.do_update = false
                packages = Autobuild::Package.each.
                    find_all { |pkg_name, pkg| File.directory?(pkg.srcdir) }.
                    delete_if { |pkg_name, pkg| Autoproj.manifest.excluded?(pkg_name) || Autoproj.manifest.ignored?(pkg_name) }

                packages.each do |_, pkg|
                    pkg.isolate_errors do
                        pkg.import
                    end
                end

            ensure
                Autobuild.do_update = old_update_flag
            end

            known_available_packages = Set.new
            all_enabled_packages = Set.new

            package_queue = selected_packages.dup
            while !package_queue.empty?
                current_packages, package_queue = package_queue, Set.new
                current_packages = current_packages.sort_by(&:name)

                current_packages.
                    delete_if { |pkg| all_enabled_packages.include?(pkg.name) }
                all_enabled_packages |= current_packages.map(&:name).to_set

                # Recursively check that no package in the selection depend on
                # excluded packages
                current_packages.each do |pkg|
                    verify_package_availability(pkg.name)
                end

                # We import first so that all packages can export the
                # additional targets they provide.
                current_packages.each do |pkg|
                    # If the package has no importer, the source directory must
                    # be there
                    if !pkg.importer && !File.directory?(pkg.srcdir)
                        raise ConfigError, "#{pkg.name} has no VCS, but is not checked out in #{pkg.srcdir}"
                    end

                    Rake::Task["#{pkg.name}-import"].invoke
                    manifest.load_package_manifest(pkg.name)
                end

                current_packages.each do |pkg|
                    verify_package_availability(pkg.name)
                    Rake::Task["#{pkg.name}-prepare"].invoke

                    # Verify that its dependencies are there, and add
                    # them to the selected_packages set so that they get
                    # imported as well
                    pkg.dependencies.each do |dep_name|
                        package_queue << Autobuild::Package[dep_name]
                    end
                end
            end

            if Autoproj.verbose
                Autoproj.progress "autoproj: finished importing packages"
            end
            if Autoproj::CmdLine.list_newest?
                fields = []
                Rake::Task.tasks.each do |task|
                    if task.kind_of?(Autobuild::SourceTreeTask)
                        task.timestamp
                        fields << ["#{task.name}:", task.newest_file, task.newest_time.to_s]
                    end
                end

                field_sizes = fields.inject([0, 0, 0]) do |sizes, line|
                    3.times do |i|
                        sizes[i] = [sizes[i], line[i].length].max
                    end
                    sizes
                end
                format = "  %-#{field_sizes[0]}s %-#{field_sizes[1]}s at %-#{field_sizes[2]}s"
                fields.each do |line|
                    Autoproj.progress(format % line)
                end
            end

            return all_enabled_packages
        end

        def self.build_packages(selected_packages, all_enabled_packages)
            if Autoproj::CmdLine.doc?
                Autoproj.progress("autoproj: building and installing documentation", :bold)
            else
                Autoproj.progress("autoproj: building and installing packages", :bold)
            end

            if Autoproj::CmdLine.update_os_dependencies?
                manifest.install_os_dependencies(all_enabled_packages)
            end

            if !selected_packages.empty? && !force_re_build_with_depends?
                if Autobuild.do_rebuild
                    selected_packages.each do |pkg_name|
                        Autobuild::Package[pkg_name].prepare_for_rebuild
                    end
                    Autobuild.do_rebuild = false
                elsif Autobuild.do_forced_build
                    selected_packages.each do |pkg_name|
                        Autobuild::Package[pkg_name].prepare_for_forced_build
                    end
                    Autobuild.do_forced_build = false
                end
            end

            Autobuild.apply(all_enabled_packages, "autoproj-build")
        end

        def self.manifest; Autoproj.manifest end
        def self.bootstrap?; !!@bootstrap end
        def self.only_status?; !!@only_status end
        def self.only_local?; !!@only_local end
        def self.check?; !!@check end
        def self.manifest_update?; !!@manifest_update end
        def self.only_config?; !!@only_config end
        def self.update_os_dependencies?; !!@update_os_dependencies end
        class << self
            attr_accessor :update_os_dependencies
            attr_accessor :snapshot_dir
            attr_writer :list_newest
        end
        def self.display_configuration?; !!@display_configuration end
        def self.force_re_build_with_depends?; !!@force_re_build_with_depends end
        def self.partial_build?; !!@partial_build end
        def self.mail_config; @mail_config || Hash.new end
        def self.update_packages?; @mode == "update" || @mode == "envsh" || build? end
        def self.build?; @mode =~ /build/ end
        def self.doc?; @mode == "doc" end
        def self.snapshot?; @mode == "snapshot" end
        def self.list_newest?; @list_newest end
        def self.parse_arguments(args)
            @only_status = false
            @only_local  = false
            @check = false
            @manifest_update = false
            @display_configuration = false
            @update_os_dependencies = nil
            update_os_dependencies  = nil
            @force_re_build_with_depends = false
            force_re_build_with_depends = nil
            @only_config = false
            @partial_build = false
            Autobuild.doc_errors = false
            Autobuild.do_doc = false
            Autobuild.only_doc = false
            Autobuild.do_update = nil
            do_update = nil

            mail_config = Hash.new

            # Parse the configuration options
            parser = OptionParser.new do |opts|
                opts.banner = <<-EOBANNER
autoproj mode [options]
where 'mode' is one of:

-- Build
  build:  import, build and install all packages that need it. A package or package
    set name can be given, in which case only this package and its dependencies
    will be taken into account. Example:

    autoproj build drivers/hokuyo

  fast-build: builds without updating and without considering OS dependencies
  full-build: updates packages and OS dependencies, and then builds 
  force-build: triggers all build commands, i.e. don't be lazy like in "build".
           If packages are selected on the command line, only those packages
           will be affected unless the --with-depends option is used.
  rebuild: clean and then rebuild. If packages are selected on the command line,
           only those packages will be affected unless the --with-depends option
           is used.
  doc:    generate and install documentation for packages that have some

-- Status & Update
  envsh: update the env.sh script
  status: displays the state of the packages w.r.t. their source VCS
  list:   list all available packages
  update: only import/update packages, do not build them
  update-config: only update the configuration

-- Autoproj Configuration
  bootstrap: starts a new autoproj installation. Usage:
    autoproj bootstrap [manifest_url|source_vcs source_url opt1=value1 opt2=value2 ...]
  switch-config: change where the configuration should be taken from. Syntax:
    autoproj switch-config source_vcs source_url opt1=value1 opt2=value2 ...

    For example:
    autoproj switch-config git git://github.com/doudou/rubim-all.git branch=all

-- Additional options:
    EOBANNER
                opts.on("--reconfigure", "re-ask all configuration options (build modes only)") do
                    Autoproj.reconfigure = true
                end
                opts.on("--version", "displays the version and then exits") do
                    STDERR.puts "autoproj v#{Autoproj::VERSION}"
                    exit(0)
                end
                opts.on("--[no-]update", "[do not] update already checked-out packages (build modes only)") do |value|
                    do_update = value
                end
                opts.on("--keep-going", "-k", "continue building even though one package has an error") do
                    Autobuild.ignore_errors = true
                end
                opts.on("--os", "displays the operating system as detected by autoproj") do
                    os = OSDependencies.operating_system
                    if !os
                        puts "no information about that OS"
                    else
                        puts "name: #{os[0]}"
                        puts "version:"
                        os[1].each do |version_name|
                            puts "  #{version_name}"
                        end
                    end
                    exit 0
                end

                opts.on("--[no-]osdeps", "[do not] install prepackaged dependencies (build and update modes only)") do |value|
                    update_os_dependencies = value
                end
                opts.on("--with-depends", "apply rebuild and force-build to both packages selected on the command line and their dependencies") do
                    force_re_build_with_depends = true
                end
                opts.on("--list-newest", "for each source directory, list what is the newest file used by autoproj for dependency tracking") do
                    Autoproj::CmdLine.list_newest = true
                end
                opts.on("--local", "for status, do not access the network") do
                    @only_local = true
                end

                opts.on("--verbose", "verbose output") do
                    Autoproj.verbose  = true
                    Autobuild.verbose = true
                    Rake.application.options.trace = false
                end
                opts.on("--debug", "debugging output") do
                    Autoproj.verbose  = true
                    Autobuild.verbose = true
                    Rake.application.options.trace = true
                    Autobuild.debug = true
                end
                opts.on('--nice NICE', Integer, 'nice the subprocesses to the given value') do |value|
                    Autobuild.nice = value
                end
                opts.on("-h", "--help", "Show this message") do
                    puts opts
                    exit
                end
                opts.on("--mail-from EMAIL", String, "From: field of the sent mails") do |from_email|
                    mail_config[:from] = from_email
                end
                opts.on("--mail-to EMAILS", String, "comma-separated list of emails to which the reports should be sent") do |emails| 
                    mail_config[:to] ||= []
                    mail_config[:to] += emails.split(',')
                end
                opts.on("--mail-subject SUBJECT", String, "Subject: field of the sent mails") do |subject_email|
                    mail_config[:subject] = subject_email
                end
                opts.on("--mail-smtp HOSTNAME", String, " address of the mail server written as hostname[:port]") do |smtp|
                    raise "invalid SMTP specification #{smtp}" unless smtp =~ /^([^:]+)(?::(\d+))?$/
                        mail_config[:smtp] = $1
                    mail_config[:port] = Integer($2) if $2 && !$2.empty?
                end
                opts.on("--mail-only-errors", "send mail only on errors") do
                    mail_config[:only_errors] = true
                end
            end

            parser.parse!(args)
            @mail_config = mail_config

            @mode = args.shift
            unknown_mode = catch(:unknown) do
                handle_mode(@mode, args)
            end
            if unknown_mode
                STDERR.puts "unknown mode #{@mode}"
                STDERR.puts "run autoproj --help for more documentation"
                exit(1)
            end

            selection = args.dup
            @partial_build = !selection.empty?
            @update_os_dependencies = update_os_dependencies if !update_os_dependencies.nil?
            @force_re_build_with_depends = force_re_build_with_depends if !force_re_build_with_depends.nil?
            Autobuild.do_update = do_update if !do_update.nil?
            selection
        end

        def self.handle_mode(mode, remaining_args)
            case mode
            when "update-sets"
                Autoproj.warn("update-sets is deprecated. Use update-config instead")
                mode = "update-config"
            when "list-sets"
                Autoproj.warn("list-sets is deprecated. Use list-config instead")
                mode = "list-config"
            end

            case mode
            when "bootstrap"
                @bootstrap = true
                bootstrap(*remaining_args)
                remaining_args.clear

                @display_configuration = true
                Autobuild.do_build = false
                Autobuild.do_update = false
                @update_os_dependencies = false
                @only_config = true

            when "switch-config"
                # We must switch to the root dir first, as it is required by the
                # configuration switch code. This is acceptable as long as we
                # quit just after the switch
                Dir.chdir(Autoproj.root_dir)
                switch_config(*remaining_args)
                exit 0

            when "build"
            when "force-build"
                Autobuild.do_forced_build = true
            when "rebuild"
                Autobuild.do_rebuild = true
            when "fast-build"
                Autobuild.do_update = false
                @update_os_dependencies = false
            when "snapshot"
                @snapshot_dir = remaining_args.shift
                Autobuild.do_update = false
                Autobuild.do_build = false
                @update_os_dependencies = false
            when "full-build"
                Autobuild.do_update = true
                @update_os_dependencies = true
            when "update"
                Autobuild.do_update = true
                Autobuild.do_build  = false
            when "check"
                Autobuild.do_update = false
                @update_os_dependencies = false
                Autobuild.do_build = false
                @check = true
            when "manifest-update"
                Autobuild.do_update = false
                @update_os_dependencies = false
                Autobuild.do_build = false
                @manifest_update = true
            when "osdeps"
                Autobuild.do_update = false
                @update_os_dependencies = true
                Autobuild.do_build  = false
            when "status"
                @only_status = true
                Autobuild.do_update = false
                @update_os_dependencies = false
            when "envsh"
                Autobuild.do_build  = false
                Autobuild.do_update = false
                @update_os_dependencies = false
            when "update-config"
                @only_config = true
                Autobuild.do_update = true
                @update_os_dependencies = true
                Autobuild.do_build = false
            when "list-config"
                @only_config = true
                @display_configuration = true
                Autobuild.do_update = false
                @update_os_dependencies = false
            when "doc"
                Autobuild.do_update = false
                @update_os_dependencies = false
                Autobuild.do_doc    = true
                Autobuild.only_doc  = true
            else
                throw :unknown, true
            end
            nil
        end

        def self.display_status(packages)
            last_was_in_sync = false

            packages.each do |pkg|
                lines = []

                pkg_name =
                    if pkg.respond_to?(:text_name)
                        pkg.text_name
                    else pkg.autoproj_name
                    end

                if !pkg.importer.respond_to?(:status)
                    lines << Autoproj.color("  the #{pkg.importer.class.name.gsub(/.*::/, '')} importer does not support status display", :bold, :red)
                elsif !File.directory?(pkg.srcdir)
                    lines << Autoproj.color("  is not imported yet", :magenta)
                else
                    status = pkg.importer.status(pkg,@only_local)
                    if status.uncommitted_code
                        lines << Autoproj.color("  contains uncommitted modifications", :red)
                    end

                    case status.status
                    when Autobuild::Importer::Status::UP_TO_DATE
                        if !status.uncommitted_code
                            if last_was_in_sync
                                STDERR.print ", #{pkg_name}"
                            else
                                STDERR.print pkg_name
                            end
                            last_was_in_sync = true
                            next
                        else
                            lines << Autoproj.color("  local and remote are in sync", :green)
                        end
                    when Autobuild::Importer::Status::ADVANCED
                        lines << Autoproj.color("  local contains #{status.local_commits.size} commit that remote does not have:", :magenta)
                        status.local_commits.each do |line|
                            lines << Autoproj.color("    #{line}", :magenta)
                        end
                    when Autobuild::Importer::Status::SIMPLE_UPDATE
                        lines << Autoproj.color("  remote contains #{status.remote_commits.size} commit that local does not have:", :magenta)
                        status.remote_commits.each do |line|
                            lines << Autoproj.color("    #{line}", :magenta)
                        end
                    when Autobuild::Importer::Status::NEEDS_MERGE
                        lines << Autoproj.color("  local and remote have diverged with respectively #{status.local_commits.size} and #{status.remote_commits.size} commits each", :magenta)
                        lines << "  -- local commits --"
                        status.local_commits.each do |line|
                            lines << Autoproj.color("   #{line}", :magenta)
                        end
                        lines << "  -- remote commits --"
                        status.remote_commits.each do |line|
                            lines << Autoproj.color("   #{line}", :magenta)
                        end
                    end
                end

                if last_was_in_sync
                    Autoproj.progress(": local and remote are in sync", :green)
                end

                last_was_in_sync = false
                STDERR.print "#{pkg_name}:"

                if lines.size == 1
                    Autoproj.progress lines.first
                else
                    Autoproj.progress
                    Autoproj.progress lines.join("\n")
                end
            end
            if last_was_in_sync
                Autoproj.progress(": local and remote are in sync", :green)
            end
        end

        def self.status(packages)
            console = Autoproj.console
            
            sources = Autoproj.manifest.each_configuration_source.
                map do |vcs, text_name, pkg_name, local_dir|
                    Autoproj::Manifest.create_autobuild_package(vcs, text_name, pkg_name, local_dir)
                end

            if !sources.empty?
                Autoproj.progress("autoproj: displaying status of configuration", :bold)
                display_status(sources)
                STDERR.puts
            end


            Autoproj.progress("autoproj: displaying status of packages", :bold)
            packages = packages.sort.map do |pkg_name|
                Autobuild::Package[pkg_name]
            end
            display_status(packages)
        end

        def self.switch_config(*args)
            Autoproj.load_config
            if Autoproj.has_config_key?('manifest_source')
                vcs = Autoproj.normalize_vcs_definition(Autoproj.user_config('manifest_source'))
            end

            if args.first =~ /^(\w+)=/
                # First argument is an option string, we are simply setting the
                # options without changing the type/url
                type, url = vcs.type, vcs.url
            else
                type, url = args.shift, args.shift
            end
            options = args

            url = VCSDefinition.to_absolute_url(url)

            if vcs && (vcs.type == type && vcs.url == url)
                # Don't need to do much: simply change the options and save the config
                # file, the VCS handler will take care of the actual switching
            else
                # We will have to delete the current autoproj directory. Ask the user.
                opt = Autoproj::BuildOption.new("delete current config", "boolean",
                            Hash[:default => "false",
                                :doc => "delete the current configuration ? (required to switch)"], nil)

                return if !opt.ask(nil)

                Dir.chdir(Autoproj.root_dir) do
                    do_switch_config(true, type, url, *options)
                end
            end

            # And now save the options: note that we keep the current option set even
            # though we switched configuration. This is not a problem as undefined
            # options will not be reused
            #
            # TODO: cleanup the options to only keep the relevant ones
            vcs_def = Hash['type' => type, 'url' => url]
            options.each do |opt|
                opt_name, opt_val = opt.split '='
                vcs_def[opt_name] = opt_val
            end
            # Validate the option hash, just in case
            Autoproj.normalize_vcs_definition(vcs_def)
            # Save the new options
            Autoproj.change_option('manifest_source', vcs_def, true)
            Autoproj.save_config
        end

        def self.do_switch_config(delete_current, type, url, *options)
            vcs_def = Hash.new
            vcs_def[:type] = type
            vcs_def[:url]  = VCSDefinition.to_absolute_url(url)
            while !options.empty?
                name, value = options.shift.split("=")
                vcs_def[name] = value
            end

            vcs = Autoproj.normalize_vcs_definition(vcs_def)

            # Install the OS dependencies required for this VCS
            handle_automatic_osdeps
            osdeps = Autoproj::OSDependencies.load_default
            osdeps.install([vcs.type])

            # Now check out the actual configuration
            config_dir = File.join(Dir.pwd, "autoproj")
            if delete_current
                # Find a backup name for it
                backup_base_name = backup_name = "#{config_dir}.bak"
                index = 0
                while File.directory?(backup_name)
                    backup_name = "#{backup_base_name}-#{index}.bak"
                    index += 1
                end
                    
                FileUtils.mv config_dir, backup_name
            end
            Autoproj::Manifest.update_source(vcs, "autoproj main configuration", 'autoproj_config', config_dir)

            # Now write it in the config file
            File.open(File.join(Autoproj.config_dir, "config.yml"), "a") do |io|
                io.puts <<-EOTEXT
manifest_source:
    type: #{vcs_def.delete(:type)}
    url: #{vcs_def.delete(:url)}
    #{vcs_def.map { |k, v| "#{k}: #{v}" }.join("\n    ")}
                EOTEXT
            end
        rescue Exception
            if backup_name
                FileUtils.rm_rf config_dir if config_dir
                FileUtils.mv backup_name, config_dir
            end
            raise
        ensure
            if backup_name
                FileUtils.rm_rf backup_name
            end
        end

        def self.bootstrap(*args)
            if File.exists?(File.join("autoproj", "manifest"))
                raise ConfigError, "this installation is already bootstrapped. Remove the autoproj directory if it is not the case"
            end

            require 'set'
            curdir_entries = Dir.entries('.').to_set - [".", "..", "autoproj_bootstrap", ".gems"].to_set
            if !curdir_entries.empty? && ENV['AUTOPROJ_BOOTSTRAP_IGNORE_NONEMPTY_DIR'] != '1'
                while true
                    print "The current directory is not empty, continue bootstrapping anyway ? [yes] "
                    STDOUT.flush
                    answer = STDIN.readline.chomp
                    if answer == "no"
                        exit
                    elsif answer == "" || answer == "yes"
                        # Set this environment variable since we might restart
                        # autoproj later on.
                        ENV['AUTOPROJ_BOOTSTRAP_IGNORE_NONEMPTY_DIR'] = '1'
                        break
                    else
                        STDOUT.puts "invalid answer. Please answer 'yes' or 'no'"
                        STDOUT.flush
                    end
                end
            end

            Autobuild.logdir = File.join(Autoproj.prefix, 'log')

            # Check if GEM_HOME is set. If it is the case, assume that we are
            # bootstrapping from another installation directory and start by
            # copying the .gems directory
            #
            # We don't use Autoproj.gem_home there as we might not be in an
            # autoproj directory at all
            gem_home = ENV['AUTOPROJ_GEM_HOME'] || File.join(Dir.pwd, ".gems")
            if ENV['GEM_HOME'] && Autoproj.in_autoproj_installation?(ENV['GEM_HOME']) &&
                ENV['GEM_HOME'] != gem_home
                if !File.exists?(gem_home)
                    Autoproj.progress "autoproj: reusing bootstrap from #{File.dirname(ENV['GEM_HOME'])}"
                    FileUtils.cp_r ENV['GEM_HOME'], gem_home
                end
                ENV['GEM_HOME'] = gem_home

                Autoproj.progress "restarting bootstrapping from #{Dir.pwd}"

                require 'rbconfig'
                ruby = RbConfig::CONFIG['RUBY_INSTALL_NAME']
                exec ruby, $0, *ARGV
            end

            # If we are not getting the installation setup from a VCS, copy the template
            # files
            if args.empty? || args.size == 1
                sample_dir = File.expand_path(File.join("..", "..", "samples"), File.dirname(__FILE__))
                FileUtils.cp_r File.join(sample_dir, "autoproj"), "autoproj"
            end

            if args.size == 1 # the user asks us to download a manifest
                manifest_url = args.first
                Autoproj.progress("autoproj: downloading manifest file #{manifest_url}", :bold)
                manifest_data =
                    begin open(manifest_url) { |file| file.read }
                    rescue
                        raise ConfigError, "cannot read #{manifest_url}, did you mean 'autoproj bootstrap VCSTYPE #{manifest_url}' ?"
                    end

                File.open(File.join(Autoproj.config_dir, "manifest"), "w") do |io|
                    io.write(manifest_data)
                end

            elsif args.size >= 2 # is a VCS definition for the manifest itself ...
                type, url, *options = *args
                url = VCSDefinition.to_absolute_url(url, Dir.pwd)
                do_switch_config(false, type, url, *options)
            end

            # Finally, generate an env.sh script
            File.open('env.sh', 'w') do |io|
                io.write <<-EOSHELL
export RUBYOPT=-rubygems
export GEM_HOME=#{Autoproj.gem_home}
export PATH=$GEM_HOME/bin:$PATH
                EOSHELL
            end
        end

        def self.missing_dependencies(pkg)
            manifest = Autoproj.manifest.package_manifests[pkg.name]
            all_deps = pkg.dependencies.map do |dep_name|
                dep_pkg = Autobuild::Package[dep_name]
                if dep_pkg then dep_pkg.name
                else dep_name
                end
            end

            if manifest
                declared_deps = manifest.each_dependency.to_a
                missing = all_deps - declared_deps
            else
                missing = all_deps
            end

            missing.to_set.to_a.sort
        end

        def self.check(packages)
            packages.sort.each do |pkg_name|
                result = []

                pkg = Autobuild::Package[pkg_name]
                manifest = Autoproj.manifest.package_manifests[pkg.name]

                # Check if the manifest contains rosdep tags
                # if manifest && !manifest.each_os_dependency.to_a.empty?
                #     result << "uses rosdep tags, convert them to normal <depend .../> tags"
                # end

                missing = missing_dependencies(pkg)
                if !missing.empty?
                    result << "missing dependency tags for: #{missing.join(", ")}"
                end

                if !result.empty?
                    Autoproj.progress pkg.name
                    Autoproj.progress "  #{result.join("\n  ")}"
                end
            end
        end

        def self.manifest_update(packages)
            packages.sort.each do |pkg_name|
                pkg = Autobuild::Package[pkg_name]
                manifest = Autoproj.manifest.package_manifests[pkg.name]

                xml = 
                    if !manifest
                        Nokogiri::XML::Document.parse("<package></package>") do |c|
                            c.noblanks
                        end
                    else
                        manifest.xml.dup
                    end

                # Add missing dependencies
                missing = missing_dependencies(pkg)
                if !missing.empty?
                    package_node = xml.xpath('/package').to_a.first
                    missing.each do |pkg_name|
                        node = Nokogiri::XML::Node.new("depend", xml)
                        node['package'] = pkg_name
                        package_node.add_child(node)
                    end
                    modified = true
                end

                # Save the manifest back
                if modified
                    path = File.join(pkg.srcdir, 'manifest.xml')
                    File.open(path, 'w') do |io|
                        io.write xml.to_xml
                    end
                    if !manifest
                        Autoproj.progress "created #{path}"
                    else
                        Autoproj.progress "modified #{path}"
                    end
                end
            end
        end

        def self.snapshot(target_dir, packages)
            # First, copy the configuration directory to create target_dir
            if File.exists?(target_dir)
                raise ArgumentError, "#{target_dir} already exists"
            end
            FileUtils.cp_r Autoproj.config_dir, target_dir

            # Now, create snapshot information for each of the packages
            version_control = []
            packages.each do |package_name|
                package  = Autobuild::Package[package_name]
                importer = package.importer
                if !importer
                    Autoproj.progress "cannot snapshot #{package_name} as it has no importer"
                    next
                elsif !importer.respond_to?(:snapshot)
                    Autoproj.progress "cannot snapshot #{package_name} as the #{importer.class} importer does not support it"
                    next
                end

                vcs_info = importer.snapshot(package, target_dir)
                if vcs_info
                    version_control << Hash[package_name, vcs_info]
                end
            end

            overrides_path = File.join(target_dir, 'overrides.yml')
            overrides =
                if File.exists?(overrides_path)
                    YAML.load(File.read(overrides_path))
                else Hash.new
                end

            if overrides['overrides']
                overrides['overrides'].concat(version_control)
            else
                overrides['overrides'] = version_control
            end

            File.open(overrides_path, 'w') do |io|
                io.write YAML.dump(overrides)
            end
        end
    end
end

