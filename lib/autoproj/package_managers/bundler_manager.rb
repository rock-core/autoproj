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

            # Filters all paths that come from other autoproj installations out
            # of GEM_PATH
            def initialize_environment
                env = ws.env

                config = ws.config

                env.add_path 'PATH', File.join(Gem.user_dir, 'bin')
                env.add_path 'PATH', File.join(ws.prefix_dir, 'gems', 'bin')
                env.add_path 'PATH', File.join(config.bundler_gem_home, 'bin')
                env.add_path 'PATH', File.join(ws.dot_autoproj_dir, 'autoproj', 'bin')
                env.set 'GEM_HOME', config.gems_gem_home

                root_dir     = File.join(ws.prefix_dir, 'gems')
                gemfile_path = File.join(root_dir, 'Gemfile')
                if File.file?(gemfile_path)
                    env.set('BUNDLE_GEMFILE', gemfile_path)
                end

                if !config.private_bundler? || !config.private_autoproj? || !config.private_gems?
                    env.set('GEM_PATH', *Gem.default_path)
                end
                if config.private_bundler?
                    Autobuild.programs['bundler'] = File.join(config.bundler_gem_home, 'bin', 'bundler')
                    env.add_path 'GEM_PATH', config.bundler_gem_home
                else
                    Autobuild.programs['bundler'] = env.find_in_path('bundler')
                end

                env.init_from_env 'RUBYLIB'
                env.inherit 'RUBYLIB'
                # Sanitize the rubylib we get from the environment by removing
                # anything that comes from Gem or Bundler
                original_rubylib =
                    (env['RUBYLIB'] || "").split(File::PATH_SEPARATOR).find_all do |p|
                        !p.start_with?(Bundler.rubygems.gem_dir) &&
                            !Bundler.rubygems.gem_path.any? { |gem_p| p.start_with?(p) }
                    end
                # And discover the system's rubylib
                if system_rubylib = discover_rubylib
                    env.system_env['RUBYLIB'] = []
                    env.original_env['RUBYLIB'] = (original_rubylib - system_rubylib).join(File::PATH_SEPARATOR)
                end

                ws.config.each_reused_autoproj_installation do |p|
                    reused_w = ws.new(p)
                    reused_c = reused_w.load_config
                    env.add_path 'PATH', File.join(reused_w.prefix_dir, 'gems', 'bin')
                end

                prefix_gems = File.join(ws.prefix_dir, "gems")
                FileUtils.mkdir_p prefix_gems
                gemfile = File.join(prefix_gems, 'Gemfile')
                if !File.exists?(gemfile)
                    File.open(gemfile, 'w') do |io|
                        io.puts "eval_gemfile \"#{File.join(ws.dot_autoproj_dir, 'autoproj', 'Gemfile')}\""
                    end
                end

                if bundle_rubylib = discover_bundle_rubylib(silent_errors: true)
                    update_env_rubylib(bundle_rubylib, system_rubylib)
                end
            end

            def update_env_rubylib(bundle_rubylib, system_rubylib = discover_rubylib)
                current = (ws.env.resolved_env['RUBYLIB'] || '').split(File::PATH_SEPARATOR) + system_rubylib
                (bundle_rubylib - current).each do |p|
                    ws.env.add_path('RUBYLIB', p)
                end
            end

            def parse_package_entry(entry)
                if entry =~ /^([^><=~]*)([><=~]+.*)$/
                    [$1.strip, $2.strip]
                else
                    [entry]
                end
            end

            class NotCleanState < RuntimeError; end

            def backup_files(mapping)
                mapping.each do |file, backup_file|
                    if File.file?(file)
                        FileUtils.cp file, backup_file
                    end
                end
            end

            def backup_restore(mapping)
                mapping.each do |file, backup_file|
                    if File.file?(backup_file)
                        FileUtils.cp backup_file, file
                    end
                end
            end

            def backup_clean(mapping)
                mapping.each do |file, backup_file|
                    if File.file?(backup_file)
                        FileUtils.rm backup_file
                    end
                end
            end

            def self.run_bundler_install(ws, gemfile, *options, update: true, binstubs: nil)
                if update && File.file?("#{gemfile}.lock")
                    FileUtils.rm "#{gemfile}.lock"
                end

                options << "--shebang" << Gem.ruby
                if binstubs
                    options << "--binstubs" << binstubs
                end

                Bundler.with_clean_env do
                    connections = Set.new
                    ws.run 'autoproj', 'osdeps',
                        Autobuild.tool('bundler'), 'install',
                            *options,
                            working_directory: File.dirname(gemfile), env: Hash['BUNDLE_GEMFILE' => nil, 'RUBYOPT' => nil] do |line|

                        case line
                        when /Installing (.*)/
                            Autobuild.message "  bundler: installing #{$1}"
                        when /Fetching.*from (.*)/
                            host = $1.gsub(/\.+$/, '')
                            if !connections.include?(host)
                                Autobuild.message "  bundler: connected to #{host}"
                                connections << host
                            end
                        end
                    end
                end
            end

            def install(gems, filter_uptodate_packages: false, install_only: false)
                root_dir     = File.join(ws.prefix_dir, 'gems')
                gemfile_path = File.join(root_dir, 'Gemfile')
                gemfile_lock_path = "#{gemfile_path}.lock"
                backups = Hash[
                    gemfile_path => "#{gemfile_path}.orig",
                    gemfile_lock_path => "#{gemfile_lock_path}.orig"
                ]

                # Back up the existing gemfile, we'll restore it if something is
                # wrong to avoid leaving bundler in an inconsistent state
                backup_files(backups)
                if !File.file?("#{gemfile_path}.orig")
                    File.open("#{gemfile_path}.orig", 'w') do |io|
                        io.puts "eval_gemfile \"#{File.join(ws.dot_autoproj_dir, 'autoproj', 'Gemfile')}\""
                    end
                end

                gemfiles = []
                ws.manifest.each_package_set do |source|
                    if source.local_dir && File.file?(pkg_set_gemfile = File.join(source.local_dir, 'Gemfile'))
                        gemfiles << pkg_set_gemfile
                    end
                end
                # In addition, look into overrides.d
                Dir.glob(File.join(ws.overrides_dir, "*.gemfile")) do |gemfile_path|
                    gemfiles << gemfile_path
                end

                # Generate the gemfile and remove the lockfile
                gemfile_lines = gems.map do |name|
                    name, version = parse_package_entry(name)
                    "gem \"#{name}\", \"#{version || ">= 0"}\""
                end
                gemfiles.each do |gemfile|
                    gemfile_lines.concat(File.readlines(gemfile).map(&:chomp))
                end
                gemfile_lines = gemfile_lines.sort.uniq
                gemfile_contents = [
                    "eval_gemfile \"#{File.join(ws.dot_autoproj_dir, 'autoproj', 'Gemfile')}\"",
                    *gemfile_lines
                ].join("\n")

                FileUtils.mkdir_p root_dir
                if updated = (!File.exist?(gemfile_path) || File.read(gemfile_path) != gemfile_contents)
                    File.open(gemfile_path, 'w') do |io|
                        io.puts gemfile_contents
                    end
                end

                options = Array.new
                if ws.config.private_gems?
                    options << "--path" << ws.config.gems_gem_home
                end

                binstubs_path = File.join(root_dir, 'bin')
                if updated || !install_only || !File.file?("#{gemfile_path}.lock")
                    self.class.run_bundler_install ws, gemfile_path, *options,
                        binstubs: binstubs_path
                end

                if bundle_rubylib = discover_bundle_rubylib
                    update_env_rubylib(bundle_rubylib)
                else
                    raise NotCleanState, "bundler executed successfully, but the result was not in a clean state"
                end

            rescue Exception => e
                Autoproj.warn "saved the new Gemfile in #{gemfile_path}.FAILED and restored the last Gemfile version"
                FileUtils.cp gemfile_path, "#{gemfile_path}.FAILED"
                backup_restore(backups)
                raise
            ensure
                FileUtils.rm_f File.join(binstubs_path, 'bundler')
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
                        io.readlines.map { |l| l.chomp }.find_all { |l| !l.empty? }
                    end
                end
            end

            def discover_bundle_rubylib(silent_errors: false)
                require 'bundler'
                gemfile = File.join(ws.prefix_dir, 'gems', 'Gemfile')
                silent_redirect = Hash.new
                if silent_errors
                    silent_redirect[:err] = '/dev/null'
                end
                Tempfile.open 'autoproj-rubylib' do |io|
                    result = Bundler.clean_system(
                        Hash['BUNDLE_GEMFILE' => gemfile],
                        Autobuild.tool('bundler'), 'exec', 'ruby', '-e', 'puts $LOAD_PATH',
                        out: io, **silent_redirect)
                        
                    if result
                        io.readlines.map { |l| l.chomp }.find_all { |l| !l.empty? }
                    end
                end
            end
        end
    end
end

