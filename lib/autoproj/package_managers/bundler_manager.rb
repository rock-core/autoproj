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

                env.original_env['GEM_PATH'] =
                    (env['GEM_PATH'] || "").split(File::PATH_SEPARATOR).find_all do |p|
                        !Workspace.in_autoproj_project?(p)
                    end.join(File::PATH_SEPARATOR)
                env.inherit 'GEM_PATH'
                env.init_from_env 'GEM_PATH'
                orig_gem_path = env.original_env['GEM_PATH'].split(File::PATH_SEPARATOR)
                env.system_env['GEM_PATH'] = Gem.default_path
                env.original_env['GEM_PATH'] = orig_gem_path.join(File::PATH_SEPARATOR)

                env.init_from_env 'RUBYLIB'
                env.inherit 'RUBYLIB'
                original_rubylib =
                    (env['RUBYLIB'] || "").split(File::PATH_SEPARATOR).find_all do |p|
                        !Workspace.in_autoproj_project?(p)
                            !p.start_with?(Bundler.rubygems.gem_dir) &&
                            !Bundler.rubygems.gem_path.any? { |gem_p| p.start_with?(p) }
                    end
                system_rubylib = discover_rubylib
                env.system_env['RUBYLIB'] = []
                env.original_env['RUBYLIB'] = (original_rubylib - system_rubylib).join(File::PATH_SEPARATOR)

                dot_autoproj = ws.dot_autoproj_dir
                if ws.config.private_bundler?
                    env.push_path 'GEM_PATH', File.join(dot_autoproj, 'bundler')
                end
                if ws.config.private_autoproj?
                    env.push_path 'GEM_PATH', File.join(dot_autoproj, 'autoproj')
                end

                ws.manifest.each_reused_autoproj_installation do |p|
                    reused_w = ws.new(p)
                    reused_c = reused_w.load_config
                    if reused_c.private_gems?
                        env.push_path 'GEM_PATH', File.join(reused_w.prefix_dir, 'gems')
                    end
                    env.push_path 'PATH', File.join(reused_w.prefix_dir, 'gems', 'bin')
                end


                gem_home = File.join(ws.prefix_dir, "gems")
                if ws.config.private_gems?
                    env.set 'GEM_HOME', gem_home
                    env.push_path 'GEM_PATH', gem_home
                end

                FileUtils.mkdir_p gem_home
                gemfile = File.join(gem_home, 'Gemfile')
                if !File.exists?(gemfile)
                    File.open(gemfile, 'w') do |io|
                        io.puts "eval_gemfile \"#{File.join(ws.dot_autoproj_dir, 'autoproj', 'Gemfile')}\""
                    end
                end

                env.set 'BUNDLE_GEMFILE', File.join(gem_home, 'Gemfile')
                env.push_path 'PATH', File.join(ws.dot_autoproj_dir, 'autoproj', 'bin')
                env.push_path 'PATH', File.join(gem_home, 'bin')
                Autobuild.programs['bundler'] = File.join(ws.dot_autoproj_dir, 'autoproj', 'bin', 'bundler')

                update_env_rubylib(system_rubylib)
            end

            def update_env_rubylib(system_rubylib = discover_rubylib)
                rubylib = discover_bundle_rubylib
                current = ws.env.resolved_env['RUBYLIB'].split(File::PATH_SEPARATOR) + system_rubylib
                (rubylib - current).each do |p|
                    ws.env.push_path('RUBYLIB', p)
                end
            end

            def parse_package_entry(entry)
                if entry =~ /^([^><=~]*)([><=~]+.*)$/
                    [$1.strip, $2.strip]
                else
                    [entry]
                end
            end

            def install(gems)
                # Generate the gemfile
                gems = gems.sort.map do |name|
                    name, version = parse_package_entry(name)
                    "gem \"#{name}\", \"#{version || ">= 0"}\""
                end.join("\n")

                root_dir = File.join(ws.prefix_dir, 'gems')
                FileUtils.mkdir_p root_dir
                gemfile = File.join(root_dir, 'Gemfile')
                File.open(gemfile, 'w') do |io|
                    io.puts "eval_gemfile \"#{File.join(ws.dot_autoproj_dir, 'autoproj', 'Gemfile')}\""
                    io.puts gems
                end

                File.open(File.join(root_dir, 'Gemfile.lock'), 'w') do |io|
                    io.write File.read(File.join(ws.dot_autoproj_dir, 'autoproj', 'Gemfile.lock'))
                end

                if ws.config.private_gems?
                    options = ['--path', root_dir]
                end

                Bundler.with_clean_env do
                    connections = Set.new
                    Autobuild::Subprocess.run 'autoproj', 'osdeps',
                        Autobuild.tool('bundler'), 'install',
                            "--gemfile=#{gemfile}", *options,
                            "--binstubs", File.join(root_dir, 'bin'),
                            env: Hash['BUNDLE_GEMFILE' => gemfile] do |line|

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

                update_env_rubylib
            end

            def discover_rubylib
                r, w = IO.pipe
                Bundler.clean_system(
                    Hash['RUBYLIB' => nil],
                    Autobuild.tool('ruby'), '-e', 'puts $LOAD_PATH',
                    out: w)
                w.close
                r.readlines.map { |l| l.chomp }.find_all { |l| !l.empty? }
            end

            def discover_bundle_rubylib
                gemfile = File.join(ws.prefix_dir, 'gems', 'Gemfile')
                r, w = IO.pipe
                Bundler.clean_system(
                    Hash['BUNDLE_GEMFILE' => gemfile],
                    Autobuild.tool('bundler'), 'exec', 'ruby', '-e', 'puts $LOAD_PATH',
                    out: w)
                w.close
                r.readlines.map { |l| l.chomp }.find_all { |l| !l.empty? }
            end
        end
    end
end

