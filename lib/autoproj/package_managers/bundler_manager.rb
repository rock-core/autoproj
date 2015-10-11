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

                env.inherit 'GEM_PATH'
                env.init_from_env 'GEM_PATH'
                env.system_env['GEM_PATH'] = Gem.default_path

                if env.original_env['GEM_HOME'].empty?
                    env.unset('GEM_HOME')
                end

                env.init_from_env 'RUBYLIB'
                env.inherit 'RUBYLIB'
                original_rubylib =
                    (env['RUBYLIB'] || "").split(File::PATH_SEPARATOR).find_all do |p|
                        !p.start_with?(Bundler.rubygems.gem_dir) &&
                            !Bundler.rubygems.gem_path.any? { |gem_p| p.start_with?(p) }
                    end
                if system_rubylib = discover_rubylib
                    env.system_env['RUBYLIB'] = []
                    env.original_env['RUBYLIB'] = (original_rubylib - system_rubylib).join(File::PATH_SEPARATOR)
                end

                ws.manifest.each_reused_autoproj_installation do |p|
                    reused_w = ws.new(p)
                    reused_c = reused_w.load_config
                    if reused_c.private_gems?
                        env.add_path 'GEM_PATH', File.join(reused_w.prefix_dir, 'gems')
                    end
                    env.add_path 'PATH', File.join(reused_w.prefix_dir, 'gems', 'bin')
                end

                gem_home = File.join(ws.prefix_dir, "gems")
                if ws.config.private_gems?
                    env.set 'GEM_HOME', gem_home
                    env.add_path 'GEM_PATH', gem_home
                end

                FileUtils.mkdir_p gem_home
                gemfile = File.join(gem_home, 'Gemfile')
                if !File.exists?(gemfile)
                    File.open(gemfile, 'w') do |io|
                        io.puts "eval_gemfile \"#{File.join(ws.dot_autoproj_dir, 'autoproj', 'Gemfile')}\""
                    end
                end

                env.set 'BUNDLE_GEMFILE', File.join(gem_home, 'Gemfile')
                env.add_path 'PATH', Gem.bindir
                env.add_path 'PATH', File.join(gem_home, 'bin')

                dot_autoproj = ws.dot_autoproj_dir
                if ws.config.private_bundler?
                    env.add_path 'PATH', File.join(dot_autoproj, 'bundler', 'bin')
                    env.add_path 'GEM_PATH', File.join(dot_autoproj, 'bundler')
                end
                env.add_path 'PATH', File.join(dot_autoproj, 'autoproj', 'bin')
                if ws.config.private_autoproj?
                    env.add_path 'GEM_PATH', File.join(dot_autoproj, 'autoproj')
                end
                Autobuild.programs['bundler'] = 'bundler'

                if bundle_rubylib = discover_bundle_rubylib
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

            def install(gems)
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

                # Generate the gemfile and remove the lockfile
                gems = gems.sort.map do |name|
                    name, version = parse_package_entry(name)
                    "gem \"#{name}\", \"#{version || ">= 0"}\""
                end.join("\n")
                FileUtils.mkdir_p root_dir
                File.open(gemfile_path, 'w') do |io|
                    io.puts "eval_gemfile \"#{File.join(ws.dot_autoproj_dir, 'autoproj', 'Gemfile')}\""
                    io.puts gems
                end
                FileUtils.rm File.join(root_dir, 'Gemfile.lock')

                binstubs_path = File.join(root_dir, 'bin')
                Bundler.with_clean_env do
                    connections = Set.new
                    Autobuild::Subprocess.run 'autoproj', 'osdeps',
                        Autobuild.tool('bundler'), 'install',
                            "--gemfile=#{gemfile_path}", *options,
                            "--binstubs", binstubs_path,
                            "--shebang", Gem.ruby,
                            env: Hash['BUNDLE_GEMFILE' => gemfile_path] do |line|

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

                if bundle_rubylib = discover_bundle_rubylib
                    update_env_rubylib(bundle_rubylib)
                else
                    raise NotCleanState, "bundler executed successfully, but the result is not in a clean state"
                end

            rescue Exception => e
                backup_restore(backups)
                raise
            ensure
                FileUtils.rm_f File.join(binstubs_path, 'bundler')
                backup_clean(backups)
            end

            def discover_rubylib
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

            def discover_bundle_rubylib
                gemfile = File.join(ws.prefix_dir, 'gems', 'Gemfile')
                Tempfile.open 'autoproj-rubylib' do |io|
                    result = Bundler.clean_system(
                        Hash['BUNDLE_GEMFILE' => gemfile],
                        Autobuild.tool('bundler'), 'exec', 'ruby', '-e', 'puts $LOAD_PATH',
                        out: io,
                        err: '/dev/null')
                    if result
                        io.readlines.map { |l| l.chomp }.find_all { |l| !l.empty? }
                    end
                end
            end
        end
    end
end

