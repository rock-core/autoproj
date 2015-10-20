require 'pathname'
require 'optparse'
require 'fileutils'
require 'yaml'

module Autoproj
    module Ops
        # This class contains the functionality necessary to install autoproj in a
        # clean root
        #
        # It can be required standalone (i.e. does not depend on anything else than
        # ruby and the ruby standard library)
        class Install
            class UnexpectedBinstub < RuntimeError; end

            # The directory in which to install autoproj
            attr_reader :root_dir
            # Content of the Gemfile generated to install autoproj itself
            attr_accessor :gemfile
            # The environment that is passed to the bundler installs
            attr_reader :env
            # The configuration hash
            attr_reader :config

            def initialize(root_dir)
                @root_dir = root_dir
                if File.file?(autoproj_gemfile_path)
                    @gemfile = File.read(autoproj_gemfile_path)
                else
                    @gemfile = default_gemfile_contents
                end

                @env = Hash.new
                env['RUBYLIB'] = []
                env['GEM_PATH'] = []
                env['GEM_HOME'] = []
                env['PATH'] = self.class.sanitize_env(ENV['PATH'] || "")
                env['BUNDLE_GEMFILE'] = []

                load_config
                @local = false
            end

            def env_for_child
                env.inject(Hash.new) do |h, (k, v)|
                    h[k] = (v.join(File::PATH_SEPARATOR) if v && !v.empty?)
                    h
                end
            end

            def apply_env(env)
                env.each do |k, v|
                    if v
                        ENV[k] = v
                    else
                        ENV.delete(k)
                    end
                end
            end

            def self.sanitize_env(value)
                value.split(File::PATH_SEPARATOR).
                    find_all { |p| !in_workspace?(p) }
            end

            def self.in_workspace?(base_dir)
                path = Pathname.new(base_dir)
                while !path.root?
                    if (path + ".autoproj").exist? || (path + "autoproj").exist?
                        return true
                    end
                    path = path.parent
                end
                return false
            end


            def dot_autoproj; File.join(root_dir, '.autoproj') end

            def autoproj_install_dir; File.join(dot_autoproj, 'autoproj') end
            # The path to the gemfile used to install autoproj
            def autoproj_gemfile_path; File.join(autoproj_install_dir, 'Gemfile') end
            def autoproj_config_path; File.join(dot_autoproj, 'config.yml') end

            # Whether we can access the network while installing
            def local?; !!@local end
            # (see #local?)
            def local=(flag); @local = flag end

            # Whether bundler should be installed locally in {#dot_autoproj}
            def private_bundler?; !!@private_bundler end
            # The path to the directory into which the bundler gem should be
            # installed
            def bundler_gem_home; @private_bundler || gem_bindir end
            # (see #private_bundler?)
            def private_bundler=(flag)
                @private_bundler =
                    if flag.respond_to?(:to_str) then File.expand_path(flag)
                    elsif flag
                        File.join(dot_autoproj, 'bundler')
                    end
            end

            # Whether autoproj should be installed locally in {#dot_autoproj}
            def private_autoproj?; !!@private_autoproj end
            # The path to the directory into which the autoproj gem should be
            # installed
            def autoproj_gem_home; @private_autoproj || gem_bindir end
            # (see #private_autoproj?)
            def private_autoproj=(flag)
                @private_autoproj =
                    if flag.respond_to?(:to_str) then File.expand_path(flag)
                    elsif flag
                        File.join(dot_autoproj, 'autoproj')
                    end
            end

            # Whether autoproj should be installed locally in {#dot_autoproj}
            #
            # Unlike for {#private_autoproj?} and {#private_bundler?}, there is
            # no default path to save the gems as we don't yet know the path to
            # the prefix directory
            def private_gems?; !!@private_gems end
            # (see #private_gems?)
            def private_gems=(value)
                @private_gems =
                    if value.respond_to?(:to_str) then File.expand_path(value)
                    else value
                    end
            end

            # Whether autoproj should prefer OS-independent packages over their
            # OS-packaged equivalents (e.g. the thor gem vs. the ruby-thor
            # Debian package)
            def prefer_indep_over_os_packages?; @prefer_indep_over_os_packages end
            # (see #private_gems?)
            def prefer_indep_over_os_packages=(flag); @prefer_indep_over_os_packages = !!flag end

            def guess_gem_program
                ruby_bin = RbConfig::CONFIG['RUBY_INSTALL_NAME']
                ruby_bindir = RbConfig::CONFIG['bindir']

                candidates = ['gem']
                if ruby_bin =~ /^ruby(.+)$/
                    candidates << "gem#{$1}" 
                end

                candidates.each do |gem_name|
                    if File.file?(gem_full_path = File.join(ruby_bindir, gem_name))
                        return gem_full_path
                    end
                end
                raise ArgumentError, "cannot find a gem program (tried #{candidates.sort.join(", ")} in #{ruby_bindir})"
            end

            # The content of the default {#gemfile}
            #
            # @param [String] autoproj_version a constraint on the autoproj version
            #   that should be used
            # @return [String]
            def default_gemfile_contents(autoproj_version = ">= 2.0.0.a")
                ["source \"https://rubygems.org\"",
                 "gem \"autoproj\", \"#{autoproj_version}\"",
                 "gem \"utilrb\", \">= 3.0.0.a\""].join("\n")
            end

            # Parse the provided command line options and returns the non-options
            def parse_options(args = ARGV)
                options = OptionParser.new do |opt|
                    opt.on '--local', 'do not access the network (may fail)' do
                        @local = true
                    end
                    opt.on '--private-bundler[=PATH]', 'install bundler locally in the workspace' do |path|
                        self.private_bundler = path || true
                    end
                    opt.on '--private-autoproj[=PATH]', 'install autoproj locally in the workspace' do |path|
                        self.private_autoproj = path || true
                    end
                    opt.on '--private-gems[=PATH]', 'install gems locally in the prefix directory' do |path|
                        self.private_gems = path || true
                    end
                    opt.on '--private[=PATH]', 'whether bundler, autoproj and the workspace gems should be installed locally in the workspace' do |path|
                        self.private_bundler = path || true
                        self.private_autoproj = path || true
                        self.private_gems = path || true
                    end
                    opt.on '--version=VERSION_CONSTRAINT', String, 'use the provided string as a version constraint for autoproj' do |version|
                        @gemfile = default_gemfile_contents(version)
                    end
                    opt.on '--gemfile=PATH', String, 'use the given Gemfile to install autoproj instead of the default' do |path|
                        @gemfile = File.read(path)
                    end
                    opt.on '--prefer-os-independent-packages', 'prefer OS-independent packages (such as a RubyGem) over their OS-packaged equivalent (e.g. the thor gem vs. the ruby-thor debian package)' do
                        @prefer_indep_over_os_packages = true
                    end
                end
                options.parse(ARGV)
            end

            def install_bundler
                gem_program  = guess_gem_program
                puts "Detected 'gem' to be #{gem_program}"

                local = ['--local'] if local?

                result = system(
                    env_for_child.merge('GEM_PATH' => "", 'GEM_HOME' => bundler_gem_home),
                    gem_program, 'install', '--no-document', '--no-format-executable',
                        *local,
                        "--bindir=#{File.join(bundler_gem_home, 'bin')}", 'bundler')

                if !result
                    STDERR.puts "FATAL: failed to install bundler in #{dot_autoproj}"
                    exit 1
                end
                File.join(bundler_gem_home, 'bin', 'bundler')
            end

            def find_bundler
                clean_env = env_for_child
                if bundler   = find_in_clean_path('bundler', gem_bindir)
                    return bundler
                end

                clean_path = env_for_child['PATH']
                STDERR.puts "cannot find 'bundler' in PATH=#{clean_path}#{File::PATH_SEPARATOR}#{gem_bindir}"
                STDERR.puts "installing it now ..."
                result = system(
                    clean_env.merge('GEM_PATH' => "", 'GEM_HOME' => bundler_gem_path),
                    Gem.ruby, '-S', 'gem', 'install', 'bundler')

                if !result
                    if ENV['PATH'] != clean_path
                        STDERR.puts "  it appears that you already have some autoproj-generated env.sh loaded"
                        STDERR.puts "  - if you are running 'autoproj upgrade', please contact the autoproj author at https://github.com/rock-core/autoproj/issues/new"
                        STDERR.puts "  - if you are running an install, try again in a console where the env.sh is not loaded"
                        exit 1
                    else
                        STDERR.puts "  the recommended action is to install it manually first by running 'gem install bundler'"
                        STDERR.puts "  or call this command again with --private-bundler to have it installed in the workspace"
                        exit 1
                    end
                end

                bundler = File.join(bundler_gem_path, 'bin', 'bundler')
                if File.exist?(bundler)
                    bundler
                else
                    STDERR.puts "gem install bundler returned successfully, but still cannot find bundler in #{bundler}"
                    nil
                end
            end

            def install_autoproj(bundler)
                # Force bundler to update. If the user does not want this, let him specify a
                # Gemfile with tighter version constraints
                lockfile = File.join(autoproj_install_dir, 'Gemfile.lock')
                if File.exist?(lockfile)
                    FileUtils.rm lockfile
                end

                clean_env = env_for_child.dup

                opts = Array.new
                opts << '--local' if local?
                if private_autoproj?
                    clean_env['GEM_PATH'] = bundler_gem_home
                    clean_env['GEM_HOME'] = nil
                    opts << "--clean" << "--path=#{autoproj_gem_home}"
                end
                binstubs_path = File.join(autoproj_install_dir, 'bin')
                result = system(clean_env.merge('GEM_HOME' => autoproj_gem_home),
                    Gem.ruby, bundler, 'install',
                        "--gemfile=#{autoproj_gemfile_path}",
                        "--shebang=#{Gem.ruby}",
                        "--binstubs=#{binstubs_path}",
                        *opts, chdir: autoproj_install_dir)

                if !result
                    STDERR.puts "FATAL: failed to install autoproj in #{dot_autoproj}"
                    exit 1
                end
            ensure
                self.class.clean_binstubs(binstubs_path)
            end

            def self.clean_binstubs(binstubs_path)
                %w{bundler bundle}.each do |bundler_bin|
                    path = File.join(binstubs_path, bundler_bin)
                    if File.file?(path)
                        FileUtils.rm path
                    end
                end

                # Now tune the binstubs to force the usage of the autoproj
                # gemfile. Otherwise, they get BUNDLE_GEMFILE from the
                # environment by default
                Dir.glob(File.join(binstubs_path, '*')) do |path|
                    next if !File.file?(path)

                    lines = File.readlines(path)
                    matched = false
                    filtered = lines.map do |l|
                        matched ||= (ENV_BUNDLE_GEMFILE_RX === l)
                        l.gsub(ENV_BUNDLE_GEMFILE_RX, '\\1=')
                    end
                    if !matched
                        raise UnexpectedBinstub, "expected #{path} to contain a line looking like ENV['BUNDLE_GEMFILE'] ||= but could not find one"
                    end
                    File.open(path, 'w') do |io|
                        io.write filtered.join("")
                    end
                end
            end

            def save_env_sh(*vars)
                env = Autobuild::Environment.new
                env.prepare
                vars.each do |kv|
                    k, *v = kv.split("=")
                    v = v.join("=")

                    if v.empty?
                        env.unset k
                    else
                        env.set k, *v.split(File::PATH_SEPARATOR)
                    end
                end
                # Generate environment files right now, we can at least use bundler
                File.open(File.join(dot_autoproj, 'env.sh'), 'w') do |io|
                    env.export_env_sh(io)
                end

                # And now the root envsh
                env = Autobuild::Environment.new
                env.source_before File.join(dot_autoproj, 'env.sh')
                env.set('AUTOPROJ_CURRENT_ROOT', root_dir)
                File.open(File.join(root_dir, 'env.sh'), 'w') do |io|
                    env.export_env_sh(io)
                end
            end

            def save_gemfile
                FileUtils.mkdir_p File.dirname(autoproj_gemfile_path)
                File.open(autoproj_gemfile_path, 'w') do |io|
                    io.write gemfile
                end
            end

            ENV_BUNDLE_GEMFILE_RX = /^(\s*ENV\[['"]BUNDLE_GEMFILE['"]\]\s*)(?:\|\|)?=/


            def find_in_clean_path(command, *additional_paths)
                clean_path = env_for_child['PATH'].split(File::PATH_SEPARATOR) + additional_paths
                clean_path.each do |p|
                    full_path = File.join(p, command)
                    if File.file?(full_path)
                        return full_path
                    end
                end
                nil
            end

            # The path of the bin/ folder for installed gems
            def gem_bindir
                return @gem_bindir if @gem_bindir

                # Here, we're getting into the esotheric
                #
                # The problem is that e.g. Ubuntu and Debian install an
                # operating_system.rb file that sets proper OS defaults. Some
                # autoproj installs have it in their RUBYLIB but should not
                # because of limitations of autoproj 1.x. This leads to
                # Gem.bindir being *not* valid for subprocesses
                #
                # So, we're calling 'gem' as a subcommand to discovery the
                # actual bindir
                bindir = IO.popen(env_for_child, [Gem.ruby, '-e', 'puts "#{Gem.user_dir}/bin"']).read
                if bindir
                    @gem_bindir = bindir.chomp
                else
                    raise "FATAL: cannot run #{Gem.ruby} -e 'puts Gem.bindir'"
                end
            end

            def install
                if private_bundler?
                    puts "Installing bundler in #{bundler_gem_home}"
                    bundler = install_bundler
                elsif bundler = find_bundler
                    puts "Detected bundler at #{bundler}"
                else
                    exit 1
                end
                save_gemfile
                puts "Installing autoproj in #{dot_autoproj}"
                install_autoproj(bundler)
            end

            def load_config
                v1_config_path = File.join(root_dir, 'autoproj', 'config.yml')
                
                config = Hash.new
                if File.file?(v1_config_path)
                    config.merge!(YAML.load(File.read(v1_config_path)))
                end
                if File.file?(autoproj_config_path)
                    config.merge!(YAML.load(File.read(autoproj_config_path)))
                end

                ruby = RbConfig::CONFIG['RUBY_INSTALL_NAME']
                ruby_bindir = RbConfig::CONFIG['bindir']
                ruby_executable = File.join(ruby_bindir, ruby)
                if current = config['ruby_executable'] # When upgrading or reinstalling
                    if current != ruby_executable
                        raise "this workspace has already been initialized using #{current}, you cannot run autoproj install with #{ruby_executable}. If you know what you're doing, delete the ruby_executable line in config.yml and try again"
                    end
                else
                    config['ruby_executable'] = ruby_executable
                end

                @config = config
                %w{private_bundler private_gems private_autoproj prefer_indep_over_os_packages}.each do |flag|
                    instance_variable_set "@#{flag}", config.fetch(flag, false)
                end
            end

            def save_config
                config['private_bundler']  = (bundler_gem_home  if private_bundler?)
                config['private_autoproj'] = (autoproj_gem_home if private_autoproj?)
                config['private_gems'] = @private_gems
                config['prefer_indep_over_os_packages'] = prefer_indep_over_os_packages?
                File.open(autoproj_config_path, 'w') { |io| YAML.dump(config, io) }
            end

            def autoproj_path
                File.join(autoproj_install_dir, 'bin', 'autoproj')
            end

            def run_autoproj(*args)
                system env_for_child.merge('BUNDLE_GEMFILE' => autoproj_gemfile_path),
                    Gem.ruby, autoproj_path, *args
            end

            def stage1
                FileUtils.mkdir_p dot_autoproj
                save_config
                install
            end

            def call_stage2
                clean_env = env_for_child
                stage2_vars = clean_env.map { |k, v| "#{k}=#{v}" }
                puts "starting the newly installed autoproj for stage2 install"
                if !run_autoproj('install-stage2', root_dir, *stage2_vars)
                    raise "failed to execute autoproj install-stage2"
                end
            end

            def stage2(*vars)
                require 'autobuild'
                puts "saving env.sh and .autoproj/env.sh"
                save_env_sh(*vars)
                puts "calling autoproj envsh"
                system(Gem.ruby, autoproj_path, 'envsh')
            end
        end
    end
end

