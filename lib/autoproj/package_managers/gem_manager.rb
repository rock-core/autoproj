module Autoproj
    module PackageManagers
        # Package manager interface for the RubyGems system
        class GemManager < Manager
            class << self
                attr_writer :with_prerelease
                attr_accessor :with_doc
            end
            @with_prerelease = false
            @with_doc = false

            def self.with_prerelease(*value)
                if value.empty?
                    @with_prerelease
                else
                    begin
                        saved_flag = @with_prerelease
                        @with_prerelease = value.first
                        yield
                    ensure
                        @with_prerelease = saved_flag
                    end
                end
            end

            # Filters all paths that come from other autoproj installations out
            # of GEM_PATH
            def initialize_environment
                env = ws.env
                env.original_env["GEM_PATH"] =
                    (env["GEM_PATH"] || "").split(File::PATH_SEPARATOR).find_all do |p|
                        !Autoproj.in_autoproj_installation?(p)
                    end.join(File::PATH_SEPARATOR)
                env.inherit "GEM_PATH"
                env.init_from_env "GEM_PATH"

                orig_gem_path = env.original_env["GEM_PATH"].split(File::PATH_SEPARATOR)
                env.system_env["GEM_PATH"] = Gem.default_path
                env.original_env["GEM_PATH"] = orig_gem_path.join(File::PATH_SEPARATOR)

                ws.config.each_reused_autoproj_installation do |p|
                    p_gems = File.join(p, ".gems")
                    if File.directory?(p_gems)
                        env.push_path "GEM_PATH", p_gems
                        env.push_path "PATH", File.join(p_gems, "bin")
                    end
                end

                @gem_home = (ENV["AUTOPROJ_GEM_HOME"] || File.join(ws.root_dir, ".gems"))
                env.push_path "GEM_PATH", gem_home
                env.set "GEM_HOME", gem_home
                env.push_path "PATH", "#{gem_home}/bin"

                # Now, reset the directories in our own RubyGems instance
                Gem.paths = env.resolved_env

                use_cache_dir
            end

            # Override the gem home detected by {initialize_environment}, or set
            # it in cases where calling {initialize_environment} is not possible
            class << self
                attr_writer :gem_home
            end

            # A global cache directory that should be used to avoid
            # re-downloading gems
            def self.cache_dir
                return unless (dir = ENV["AUTOBUILD_CACHE_DIR"])

                dir = File.join(dir, "gems")
                FileUtils.mkdir_p dir
                dir
            end

            def self.use_cache_dir
                # If there is a cache directory, make sure .gems/cache points to
                # it (there are no programmatic ways to override this)
                return unless (cache = cache_dir)

                gem_cache_dir = File.join(gem_home, "cache")
                if !File.symlink?(gem_cache_dir) || File.readlink(gem_cache_dir) != cache
                    FileUtils.mkdir_p gem_home
                    FileUtils.rm_rf gem_cache_dir
                    Autoproj.create_symlink(cache, gem_cache_dir)
                end
            end

            # Return the directory in which RubyGems package should be installed
            class << self
                attr_reader :gem_home
            end

            @gem_home = nil

            # Returns the set of default options that are added to gem
            #
            # By default, we add --no-user-install to un-break distributions
            # like Arch that set --user-install by default (thus disabling the
            # role of GEM_HOME)
            def self.default_install_options
                @default_install_options ||= ["--no-user-install", "--no-format-executable"]
            end

            def initialize(ws)
                super(ws)
                @installed_gems = Set.new
            end

            # Used to override the Gem::SpecFetcher object used by this gem
            # manager. Useful mainly for testing
            attr_writer :gem_fetcher

            # The set of gems installed during this autoproj session
            attr_reader :installed_gems

            def gem_fetcher
                unless @gem_fetcher
                    Autoproj.message "  looking for RubyGems updates"
                    @gem_fetcher = Gem::SpecFetcher.fetcher
                end
                @gem_fetcher
            end

            def guess_gem_program
                return Autobuild.programs["gem"] if Autobuild.programs["gem"]

                ruby_bin = RbConfig::CONFIG["RUBY_INSTALL_NAME"]
                ruby_bindir = RbConfig::CONFIG["bindir"]

                candidates = ["gem"]
                candidates << "gem#{$1}" if ruby_bin =~ /^ruby(.+)$/

                candidates.each do |gem_name|
                    if File.file?(gem_full_path = File.join(ruby_bindir, gem_name))
                        Autobuild.programs["gem"] = gem_full_path
                        return
                    end
                end

                raise ArgumentError, "cannot find a gem program (tried #{candidates.sort.join(', ')} in #{ruby_bindir})"
            end

            def build_gem_cmdlines(gems)
                with_version, without_version = gems.partition { |name, v| v }

                cmdlines = []
                cmdlines << without_version.flatten unless without_version.empty?
                with_version.each do |name, v|
                    cmdlines << [name, "-v", v]
                end
                cmdlines
            end

            def pristine(gems)
                guess_gem_program
                base_cmdline = [Autobuild.tool_in_path("ruby", env: ws.env), "-S", Autobuild.tool("gem")]
                cmdlines = [
                    [*base_cmdline, "clean"]
                ]
                cmdlines += build_gem_cmdlines(gems).map do |line|
                    base_cmdline + ["pristine", "--extensions"] + line
                end
                if gems_interaction(gems, cmdlines)
                    Autoproj.message "  restoring RubyGems: #{gems.map { |g| g.join(' ') }.sort.join(', ')}"
                    cmdlines.each do |c|
                        Autobuild::Subprocess.run "autoproj", "osdeps", *c
                    end
                end
            end

            def install(gems)
                guess_gem_program

                base_cmdline = [Autobuild.tool_in_path("ruby", env: ws.env), "-S", Autobuild.tool("gem"), "install", *GemManager.default_install_options]
                base_cmdline << "--no-rdoc" << "--no-ri" unless GemManager.with_doc

                base_cmdline << "--prerelease" if GemManager.with_prerelease

                cmdlines = build_gem_cmdlines(gems).map do |line|
                    base_cmdline + line
                end
                if gems_interaction(gems, cmdlines)
                    Autoproj.message "  installing/updating RubyGems dependencies: #{gems.map { |g| g.join(' ') }.sort.join(', ')}"

                    cmdlines.each do |c|
                        Autobuild::Subprocess.run "autoproj", "osdeps", *c,
                                                  env: Hash["GEM_HOME" => Gem.paths.home,
                                                            "GEM_PATH" => Gem.paths.path.join(":")]
                    end
                    gems.each do |name, v|
                        installed_gems << name
                    end
                    true
                end
            end

            # Returns the set of RubyGem packages in +packages+ that are not already
            # installed, or that can be upgraded
            def filter_uptodate_packages(gems, options = Hash.new)
                options = validate_options options,
                                           install_only: !Autobuild.do_update

                # Don't install gems that are already there ...
                gems = gems.dup
                gems.delete_if do |name, version|
                    next(true) if installed_gems.include?(name)

                    version_requirements = Gem::Requirement.new(version || ">= 0")
                    installed =
                        if Gem::Specification.respond_to?(:find_by_name)
                            begin
                                [Gem::Specification.find_by_name(name, version_requirements)]
                            rescue Gem::LoadError
                                []
                            end
                        else
                            Gem.source_index.find_name(name, version_requirements)
                        end

                    if !installed.empty? && !options[:install_only]
                        # Look if we can update the package ...
                        dep = Gem::Dependency.new(name, version_requirements)
                        available =
                            if gem_fetcher.respond_to?(:find_matching)
                                non_prerelease = gem_fetcher.find_matching(dep, true, true).map(&:first)
                                if GemManager.with_prerelease
                                    prerelease = gem_fetcher.find_matching(dep, false, true, true).map(&:first)
                                else prerelease = Array.new
                                end
                                (non_prerelease + prerelease)
                                    .map { |n, v, _| [n, v] }

                            else # Post RubyGems-2.0
                                type = if GemManager.with_prerelease then :complete
                                       else :released
                                       end

                                gem_fetcher.detect(type) do |tuple|
                                    tuple.name == name && dep.match?(tuple)
                                end.map { |tuple, _| [tuple.name, tuple.version] }
                            end
                        installed_version = installed.map(&:version).max
                        available_version = available.map { |_, v| v }.max
                        unless available_version
                            if version
                                raise ConfigError.new, "cannot find any gem with the name '#{name}' and version #{version}"
                            else
                                raise ConfigError.new, "cannot find any gem with the name '#{name}'"
                            end
                        end
                        needs_update = (available_version > installed_version)
                        !needs_update
                    else
                        !installed.empty?
                    end
                end
                gems
            end

            def parse_package_entry(entry)
                if entry =~ /^([^><=~]*)([><=~]+.*)$/
                    [$1.strip, $2.strip]
                else
                    [entry]
                end
            end

            def gems_interaction(gems, cmdlines)
                if OSPackageInstaller.force_osdeps
                    return true
                elsif enabled?
                    return true
                elsif silent?
                    return false
                end

                # We're not supposed to install rubygem packages but silent is not
                # set, so display information about them anyway
                puts <<-EOMSG
      #{Autoproj.color('The build process and/or the packages require some Ruby Gems to be installed', :bold)}
      #{Autoproj.color('and you required autoproj to not do it itself', :bold)}
        You can use the --all or --ruby options to autoproj osdeps to install these
        packages anyway, and/or change to the osdeps handling mode by running an
        autoproj operation with the --reconfigure option as for instance
        autoproj build --reconfigure
      #{'  '}
        The following command line can be used to install them manually
      #{'  '}
          #{cmdlines.map { |c| c.join(' ') }.join("\n      ")}
      #{'  '}
        Autoproj expects these Gems to be installed in #{GemManager.gem_home} This can
        be overridden by setting the AUTOPROJ_GEM_HOME environment variable manually

                EOMSG
                print "    #{Autoproj.color('Press ENTER to continue ', :bold)}"

                STDOUT.flush
                STDIN.readline
                puts
                false
            end
        end
    end
end
