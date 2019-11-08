require 'bundler'
module Autoproj
    module PackageManagers
        # Package manager interface for the RubyGems system
        class BundlerManager < Manager
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

            # Directory with cached .gem packages
            #
            # The directory must exist, but may be empty.
            # It is initialized with {BundlerManager.cache_dir}
            #
            # @return [String]
            attr_accessor :cache_dir

            # (see Manager#call_while_empty?)
            def call_while_empty?
                !workspace_configuration_gemfiles.empty?
            end

            # (see Manager#strict?)
            def strict?
                true
            end

            # Set up the workspace environment to work with the bundler-managed
            # gems
            def initialize_environment
                env = ws.env

                config = ws.config

                env.add_path 'PATH', File.join(ws.prefix_dir, 'gems', 'bin')
                env.add_path 'PATH', File.join(ws.dot_autoproj_dir, 'bin')
                env.set 'GEM_HOME', config.gems_gem_home
                env.clear 'GEM_PATH'

                gemfile_path = File.join(ws.prefix_dir, 'gems', 'Gemfile')
                env.set('BUNDLE_GEMFILE', gemfile_path) if File.file?(gemfile_path)

                if cache_dir && File.exist?(cache_dir)
                    vendor_dir = File.join(File.dirname(gemfile_path), 'vendor')
                    FileUtils.mkdir_p vendor_dir
                    bundler_cache_dir = File.join(vendor_dir, 'cache')
                    if File.writable?(cache_dir)
                        create_cache_symlink(cache_dir, bundler_cache_dir)
                    else
                        Autoproj.warn "BundlerManager: #{cache_dir} is read-only "\
                                      "copying the cache instead of symlinking it"
                        create_cache_copy(cache_dir, bundler_cache_dir)
                    end
                end

                Autobuild.programs['bundler'] =
                    Autobuild.programs['bundle'] =
                    File.join(ws.dot_autoproj_dir, 'bin', 'bundle')

                env.init_from_env 'RUBYLIB'
                env.inherit 'RUBYLIB'
                # Sanitize the rubylib we get from the environment by removing
                # anything that comes from Gem or Bundler
                original_rubylib =
                    (env['RUBYLIB'] || "").split(File::PATH_SEPARATOR).find_all do |p|
                        !p.start_with?(Bundler.rubygems.gem_dir) &&
                            Bundler.rubygems.gem_path
                                   .none? { |gem_p| p.start_with?(gem_p) }
                    end
                # And discover the system's rubylib
                if (system_rubylib = discover_rubylib)
                    # Do not explicitely add the system rubylib to the
                    # environment, the interpreter will do it for us.
                    #
                    # This allows to use a binstub generated for one of ruby
                    # interpreter version on our workspace
                    env.system_env['RUBYLIB'] = []
                    env.original_env['RUBYLIB'] = (original_rubylib - system_rubylib)
                                                  .join(File::PATH_SEPARATOR)
                end

                ws.config.each_reused_autoproj_installation do |p|
                    reused_w = ws.new(p)
                    env.add_path 'PATH', File.join(reused_w.prefix_dir, 'gems', 'bin')
                end

                prefix_gems = File.join(ws.prefix_dir, "gems")
                FileUtils.mkdir_p prefix_gems
                gemfile = File.join(prefix_gems, 'Gemfile')
                unless File.exist?(gemfile)
                    Ops.atomic_write(gemfile) do |io|
                        dot_autoproj_gemfile = File.join(ws.dot_autoproj_dir, 'Gemfile')
                        io.puts "eval_gemfile \"#{dot_autoproj_gemfile}\""
                    end
                end

                if (bundle_rubylib = discover_bundle_rubylib(silent_errors: true))
                    update_env_rubylib(bundle_rubylib, system_rubylib)
                end
            end

            def create_cache_symlink(cache_dir, bundler_cache_dir)
                valid = !File.exist?(bundler_cache_dir) ||
                        File.symlink?(bundler_cache_dir)

                unless valid
                    Autoproj.warn "cannot use #{cache_dir} as gem cache as "\
                                  "#{bundler_cache_dir} already exists"
                    return
                end

                FileUtils.rm_f bundler_cache_dir
                FileUtils.ln_s cache_dir, bundler_cache_dir
            end

            def create_cache_copy(cache_dir, bundler_cache_dir)
                valid = !File.exist?(bundler_cache_dir) ||
                        File.directory?(bundler_cache_dir) ||
                        File.symlink?(bundler_cache_dir)

                unless valid
                    Autoproj.warn "cannot use #{cache_dir} as gem cache as "\
                                  "#{bundler_cache_dir} already exists"
                    return
                end

                # Gracefully upgrade from the symlinks
                FileUtils.rm_f bundler_cache_dir if File.symlink?(bundler_cache_dir)
                FileUtils.mkdir_p bundler_cache_dir

                Dir.glob(File.join(cache_dir, '*.gem')) do |path_src|
                    path_dest = File.join(bundler_cache_dir, File.basename(path_src))
                    next if File.exist?(path_dest)

                    FileUtils.cp path_src, path_dest
                end
            end

            # Enumerate the per-gem build configurations
            def self.per_gem_build_config(ws)
                ws.config.get('bundler.build', {})
            end

            # Add new build configuration arguments for a given gem
            #
            # This is meant to be used from the Autoproj configuration files,
            # e.g. overrides.rb or package configuration
            def self.add_build_configuration_for(gem_name, build_config, ws: Autoproj.workspace)
                c = ws.config.get('bundler.build', {})
                c[gem_name] = [c[gem_name], build_config].compact.join(" ")
                ws.config.set('bundler.build', c)
            end

            # Set the build configuration for the given gem
            #
            # This is meant to be used from the Autoproj configuration files,
            # e.g. overrides.rb or package configuration
            def self.configure_build_for(gem_name, build_config, ws: Autoproj.workspace)
                c = ws.config.get('bundler.build', {})
                c[gem_name] = build_config
                ws.config.set('bundler.build', c)
            end

            # Removes build configuration flags for the given gem
            #
            # This is meant to be used from the Autoproj configuration files,
            # e.g. overrides.rb or package configuration
            def self.remove_build_configuration_for(gem_name, ws: Autoproj.workspace)
                c = ws.config.get('bundler.build', {})
                c.delete(gem_name)
                ws.config.set('bundler.build', c)
            end

            # @api private
            #
            # Apply configured per-gem build configuration options
            #
            # @param [Workspace] ws the workspace whose bundler configuration
            #   should be updated
            # @return [void]
            def self.apply_build_config(ws)
                root_dir = File.join(ws.prefix_dir, 'gems')
                current_config_path = File.join(root_dir, ".bundle", "config")
                current_config =
                    if File.file?(current_config_path)
                        File.readlines(current_config_path)
                    else
                        []
                    end

                build_config = {}
                per_gem_build_config(ws).each do |name, conf|
                    build_config[name.upcase] = conf
                end

                new_config = current_config.map do |line|
                    next(line) unless (m = line.match(/BUNDLE_BUILD__(.*): "(.*)"$/))
                    next unless (desired_config = build_config.delete(m[1]))

                    if m[2] != desired_config
                        "BUNDLE_BUILD__#{m[1]}: \"#{desired_config}\""
                    else
                        line
                    end
                end.compact

                build_config.each do |name, config|
                    new_config << "BUNDLE_BUILD__#{name}: \"#{config}\""
                end

                if new_config != current_config
                    FileUtils.mkdir_p File.dirname(current_config_path)
                    File.open(current_config_path, 'w') do |io|
                        io.write new_config.join
                    end
                end
            end

            # @api private
            #
            # Update RUBYLIB to add the gems that are part of the bundler
            # install
            #
            # @param [Array<String>] bundle_rubylib the rubylib entries reported
            #   by bundler
            # @param [Array<String>] system_rubylib the rubylib entries that are
            #   set by the underlying ruby interpreter itself
            def update_env_rubylib(bundle_rubylib, system_rubylib = discover_rubylib)
                current = (ws.env.resolved_env['RUBYLIB'] || '')
                          .split(File::PATH_SEPARATOR) + system_rubylib
                (bundle_rubylib - current).each do |p|
                    ws.env.add_path('RUBYLIB', p)
                end
            end

            # @api private
            #
            # Parse an osdep entry into a gem name and gem version
            #
            # The 'gem' entries in the osdep files can contain a version
            # specification. This method parses the two parts and return them
            #
            # @param [String] entry the osdep entry
            # @return [(String,String),(String,nil)] the gem name, and an
            #   optional version specification
            def parse_package_entry(entry)
                if entry =~ /^([^><=~]*)([><=~]+.*)$/
                    [$1.strip, $2.strip]
                else
                    [entry]
                end
            end

            class NotCleanState < RuntimeError; end

            # @api private
            #
            # Create backup files matching a certain file mapping
            #
            # @param [Hash<String,String>] mapping a mapping from the original
            #   file to the file into which it should be backed up. The source
            #   file might not exist.
            def backup_files(mapping)
                mapping.each do |file, backup_file|
                    FileUtils.cp file, backup_file if File.file?(file)
                end
            end

            # @api private
            #
            # Restore backups saved by {#backup_file}
            #
            # @param (see #backup_file)
            def backup_restore(mapping)
                mapping.each do |file, backup_file|
                    FileUtils.cp backup_file, file if File.file?(backup_file)
                end
            end

            # @api private
            #
            # Remove backups created by {#backup_files}
            #
            # @param (see #backup_file)
            def backup_clean(mapping)
                mapping.each do |_file, backup_file|
                    FileUtils.rm backup_file if File.file?(backup_file)
                end
            end

            def self.run_bundler_install(ws, gemfile, *options,
                                         update: true, binstubs: nil,
                                         gem_home: ws.config.gems_gem_home,
                                         gem_path: ws.config.gems_install_path)
                FileUtils.rm "#{gemfile}.lock" if update && File.file?("#{gemfile}.lock")

                options << '--path' << gem_path
                options << "--shebang" << Gem.ruby
                options << "--binstubs" << binstubs if binstubs

                apply_build_config(ws)

                connections = Set.new
                run_bundler(ws, 'install', *options,
                            gem_home: gem_home, gemfile: gemfile) do |line|
                    case line
                    when /Installing (.*)/
                        Autobuild.message "  bundler: installing #{$1}"
                    when /Fetching.*from (.*)/
                        host = $1.gsub(/\.+$/, '')
                        unless connections.include?(host)
                            Autobuild.message "  bundler: connected to #{host}"
                            connections << host
                        end
                    end
                end
            end

            def self.bundle_gem_path(ws, gem_name, gem_home: nil, gemfile: nil)
                path = String.new
                PackageManagers::BundlerManager.run_bundler(
                    ws, 'show', gem_name,
                    gem_home: gem_home,
                    gemfile: gemfile) { |line| path << line }
                path.chomp
            end

            def self.default_bundler(ws)
                File.join(ws.dot_autoproj_dir, 'bin', 'bundle')
            end

            def self.run_bundler(ws, *commandline,
                                 gem_home: ws.config.gems_gem_home,
                                 gemfile: default_gemfile_path(ws))
                bundle = Autobuild.programs['bundle'] || default_bundler(ws)

                Bundler.with_clean_env do
                    target_env = Hash[
                        'GEM_HOME' => gem_home,
                        'GEM_PATH' => nil,
                        'BUNDLE_GEMFILE' => gemfile,
                        'RUBYOPT' => nil,
                        'RUBYLIB' => rubylib_for_bundler
                    ]
                    ws.run('autoproj', 'osdeps',
                           bundle, *commandline,
                           working_directory: File.dirname(gemfile),
                           env: target_env) { |line| yield(line) if block_given? }
                end
            end

            # Parse the contents of a gemfile into a set of
            def merge_gemfiles(*path, unlock: [])
                gems_remotes = Set.new
                dependencies = Hash.new do |h, k|
                    h[k] = Hash.new do |i, j|
                        i[j] = Hash.new do |a, b|
                            a[b] = Array.new
                        end
                    end
                end
                path.each do |gemfile|
                    bundler_def =
                        begin Bundler::Dsl.evaluate(gemfile, nil, [])
                        rescue Exception => e
                            cleaned_message = e
                                .message
                                .gsub(/There was an error parsing([^:]+)/,
                                      "Error in gem definitions")
                                .gsub(/#  from.*/, '')
                            raise ConfigError, cleaned_message
                        end
                    gems_remotes |= bundler_def.send(:sources).rubygems_remotes.to_set
                    bundler_def.dependencies.each do |d|
                        d.groups.each do |group_name|
                            if !d.platforms.empty?
                                d.platforms.each do |platform_name|
                                    dependencies[group_name][platform_name][d.name] = d
                                end
                            else
                                dependencies[group_name][''][d.name] = d
                            end
                        end
                    end
                end

                contents = []
                gems_remotes.each do |g|
                    g = g.to_s
                    g = g[0..-2] if g.end_with?('/')
                    contents << "source '#{g}'"
                end
                valid_keys = %w[group groups git path glob name branch ref tag
                                require submodules platform platforms type
                                source install_if]
                dependencies.each do |group_name, by_platform|
                    contents << "group :#{group_name} do"
                    by_platform.each do |platform_name, deps|
                        deps = deps.values.sort_by(&:name)
                        unless platform_name.empty?
                            contents << "  platform :#{platform_name} do"
                            platform_indent = "  "
                        end
                        deps.each do |d|
                            if d.source
                                options = d.source.options.dup
                                options.delete_if { |k, _| !valid_keys.include?(k) }
                                options = options.map { |k, v| "#{k}: \"#{v}\"" }
                            end
                            contents << ["  #{platform_indent}gem \"#{d.name}\",
                                         \"#{d.requirement}\"", *options].join(', ')
                        end
                        contents << '  end' unless platform_name.empty?
                    end
                    contents << 'end'
                end
                contents.join("\n")
            end

            def workspace_configuration_gemfiles
                gemfiles = []
                ws.manifest.each_package_set do |source|
                    pkg_set_gemfile = File.join(source.local_dir, 'Gemfile')
                    if source.local_dir && File.file?(pkg_set_gemfile)
                        gemfiles << pkg_set_gemfile
                    end
                end
                # In addition, look into overrides.d
                Dir.glob(File.join(ws.overrides_dir, "*.gemfile")) do |overrides_gemfile|
                    gemfiles << overrides_gemfile
                end
                gemfiles
            end

            def self.default_gemfile_path(ws)
                File.join(ws.prefix_dir, 'gems', 'Gemfile')
            end

            def install(gems, filter_uptodate_packages: false, install_only: false)
                gemfile_path = self.class.default_gemfile_path(ws)
                root_dir = File.dirname(gemfile_path)
                gemfile_lock_path = "#{gemfile_path}.lock"
                backups = Hash[
                    gemfile_path => "#{gemfile_path}.orig",
                    gemfile_lock_path => "#{gemfile_lock_path}.orig"
                ]

                # Back up the existing gemfile, we'll restore it if something is
                # wrong to avoid leaving bundler in an inconsistent state
                backup_files(backups)
                unless File.file?("#{gemfile_path}.orig")
                    Ops.atomic_write("#{gemfile_path}.orig") do |io|
                        dot_autoproj_gemfile = File.join(ws.dot_autoproj_dir, 'Gemfile')
                        io.puts "eval_gemfile \"#{dot_autoproj_gemfile}\""
                    end
                end

                gemfiles = workspace_configuration_gemfiles
                gemfiles << File.join(ws.dot_autoproj_dir, 'Gemfile')

                # Save the osdeps entries in a temporary gemfile and finally
                # merge the whole lot of it
                gemfile_contents = Tempfile.open 'autoproj-gemfile' do |io|
                    gems.sort.each do |name|
                        name, version = parse_package_entry(name)
                        io.puts "gem \"#{name}\", \"#{version || '>= 0'}\""
                    end
                    io.flush
                    gemfiles.unshift io.path
                    # The autoproj gemfile needs to be last, we really don't
                    # want to mess it up
                    merge_gemfiles(*gemfiles)
                end

                FileUtils.mkdir_p root_dir
                updated = (!File.exist?(gemfile_path) ||
                           File.read(gemfile_path) != gemfile_contents)
                if updated
                    Ops.atomic_write(gemfile_path) do |io|
                        io.puts "ruby \"#{RUBY_VERSION}\" if respond_to?(:ruby)"
                        io.puts gemfile_contents
                    end
                end

                options = Array.new
                binstubs_path = File.join(root_dir, 'bin')
                if updated || !install_only || !File.file?("#{gemfile_path}.lock")
                    self.class.run_bundler_install(ws, gemfile_path, *options,
                                                   binstubs: binstubs_path)
                end

                if (bundle_rubylib = discover_bundle_rubylib)
                    update_env_rubylib(bundle_rubylib)
                else
                    raise NotCleanState, "bundler executed successfully, "\
                                         "but the result was not in a clean state"
                end
            rescue Exception
                Autoproj.warn "saved the new Gemfile in #{gemfile_path}.FAILED "\
                              "and restored the last Gemfile version"
                FileUtils.cp gemfile_path, "#{gemfile_path}.FAILED"
                backup_restore(backups)
                raise
            ensure
                if binstubs_path
                    FileUtils.rm_f File.join(binstubs_path, 'bundle')
                    FileUtils.rm_f File.join(binstubs_path, 'bundler')
                end
                backup_clean(backups)
            end

            def discover_rubylib
                require 'bundler'
                Tempfile.open 'autoproj-rubylib' do |io|
                    result = Bundler.clean_system(
                        Hash['RUBYLIB' => nil],
                        Autobuild.tool('ruby'), '-e', 'puts $LOAD_PATH',
                        out: io,
                        err: '/dev/null')
                    if result
                        io.rewind
                        io.readlines.map(&:chomp).find_all { |l| !l.empty? }
                    end
                end
            end

            def self.rubylib_for_bundler
                rx = Regexp.new("/gems/#{Regexp.quote("bundler-#{Bundler::VERSION}")}/")
                $LOAD_PATH.grep(rx).join(File::PATH_SEPARATOR)
            end

            def discover_bundle_rubylib(silent_errors: false)
                require 'bundler'
                gemfile = File.join(ws.prefix_dir, 'gems', 'Gemfile')
                silent_redirect = Hash.new
                silent_redirect[:err] = :close if silent_errors
                env = ws.env.resolved_env
                Tempfile.open 'autoproj-rubylib' do |io|
                    result = Bundler.clean_system(
                        Hash['GEM_HOME' => env['GEM_HOME'], 'GEM_PATH' => env['GEM_PATH'],
                             'BUNDLE_GEMFILE' => gemfile, 'RUBYOPT' => nil,
                             'RUBYLIB' => self.class.rubylib_for_bundler],
                        Autobuild.tool('ruby'), '-rbundler/setup',
                        '-e', 'puts $LOAD_PATH',
                        out: io, **silent_redirect)

                    if result
                        io.rewind
                        io.readlines.map(&:chomp).find_all { |l| !l.empty? }
                    end
                end
            end
        end
    end
end
