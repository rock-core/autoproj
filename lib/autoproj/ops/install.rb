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

            def initialize(root_dir)
                @root_dir = root_dir
                @gemfile  = default_gemfile_contents
                @private_bundler  = false
                @private_autoproj = false
                @private_gems     = false
                @local = false
                @env = self.class.clean_env
            end

            def self.clean_env
                env = Hash.new
                env['RUBYLIB'] = []
                env['GEM_PATH'] = []
                %w{PATH GEM_HOME}.each do |name|
                    env[name] = sanitize_env(ENV[name] || "")
                end
                env['BUNDLE_GEMFILE'] = nil
                env
            end

            def env_for_child
                env.inject(Hash.new) do |h, (k, v)|
                    h[k] = (v.join(File::PATH_SEPARATOR) if v && !v.empty?)
                    h
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
            def bin_dir; File.join(dot_autoproj, 'bin') end
            def bundler_install_dir; File.join(dot_autoproj, 'bundler') end
            def autoproj_install_dir; File.join(dot_autoproj, 'autoproj') end
            # The path to the gemfile used to install autoproj
            def autoproj_gemfile_path; File.join(autoproj_install_dir, 'Gemfile') end
            def autoproj_config_path; File.join(dot_autoproj, 'config.yml') end

            # Whether we can access the network while installing
            def local?; !!@local end
            # (see #local?)
            def local=(flag); @local = flag end

            # Whether bundler should be installed locally in {#dot_autoproj}
            def private_bundler?; @private_bundler end
            # (see #private_bundler?)
            def private_bundler=(flag); @private_bundler = flag end
            # Whether autoproj should be installed locally in {#dot_autoproj}
            def private_autoproj?; @private_autoproj end
            # (see #private_autoproj?)
            def private_autoproj=(flag); @private_autoproj = flag end
            # Whether bundler should be installed locally in the workspace
            # prefix directory
            def private_gems?; @private_gems end
            # (see #private_gems?)
            def private_gems=(flag); @private_gems = flag end

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
                    opt.on '--private-bundler', 'install bundler locally in the workspace' do
                        @private_bundler = true
                    end
                    opt.on '--private-autoproj', 'install autoproj locally in the workspace' do
                        @private_autoproj = true
                    end
                    opt.on '--private-gems', 'install gems locally in the prefix directory' do
                        @private_gems = true
                    end
                    opt.on '--private', 'whether bundler, autoproj and the workspace gems should be installed locally in the workspace' do
                        @private_bundler = true
                        @private_autoproj = true
                        @private_gems = true
                    end
                    opt.on '--version=VERSION_CONSTRAINT', String, 'use the provided string as a version constraint for autoproj' do |version|
                        @gemfile = default_gemfile_contents(version)
                    end
                    opt.on '--gemfile=PATH', String, 'use the given Gemfile to install autoproj instead of the default' do |path|
                        @gemfile = File.read(path)
                    end
                end
                options.parse(ARGV)
            end

            def install_bundler
                gem_program  = guess_gem_program
                puts "Detected 'gem' to be #{gem_program}"

                local = ['--local'] if local?

                result = system(
                    env_for_child.merge('GEM_PATH' => nil, 'GEM_HOME' => bundler_install_dir),
                    gem_program, 'install', '--no-document', '--no-user-install', '--no-format-executable',
                        *local,
                        "--bindir=#{File.join(bundler_install_dir, 'bin')}", 'bundler')

                if !result
                    STDERR.puts "FATAL: failed to install bundler in #{dot_autoproj}"
                    exit 1
                end
                env['GEM_PATH'] << bundler_install_dir
                env['PATH'] << File.join(bundler_install_dir, 'bin')
                File.join(bin_dir, 'bundler')
            end

            def save_env_sh
                env = Autobuild::Environment.new
                env.prepare

                %w{GEM_HOME GEM_PATH}.each do |name|
                    value = self.env[name]
                    if value.empty?
                        env.unset name
                    else
                        env.set name, *value
                    end
                end
                env.push_path 'PATH', File.join(autoproj_install_dir, 'bin')

                if private_autoproj?
                    env.push_path 'GEM_PATH', autoproj_install_dir
                end

                # Generate environment files right now, we can at least use bundler
                File.open(File.join(dot_autoproj, 'env.sh'), 'w') do |io|
                    env.export_env_sh(io)
                end

                File.open(File.join(root_dir, 'env.sh'), 'w') do |io|
                    io.write <<-EOSHELL
source "#{File.join(dot_autoproj, 'env.sh')}"
export AUTOPROJ_CURRENT_ROOT=#{root_dir}
                    EOSHELL
                end
            end

            def save_gemfile
                FileUtils.mkdir_p File.dirname(autoproj_gemfile_path)
                File.open(autoproj_gemfile_path, 'w') do |io|
                    io.write gemfile
                end
            end

            def install_autoproj(bundler)
                # Force bundler to update. If the user does not want this, let him specify a
                # Gemfile with tighter version constraints
                lockfile = File.join(File.dirname(autoproj_gemfile_path), 'Gemfile.lock')
                if File.exist?(lockfile)
                    FileUtils.rm lockfile
                end

                opts = Array.new
                opts << '--local' if local?

                env = env_for_child
                if private_autoproj?
                    env = env.merge(
                        'GEM_PATH' => bundler_install_dir,
                        'GEM_HOME' => nil)
                    opts << "--clean" << "--path=#{autoproj_install_dir}"
                end

                binstubs_path = File.join(autoproj_install_dir, 'bin')

                result = system(env,
                    Gem.ruby, bundler, 'install',
                        "--gemfile=#{autoproj_gemfile_path}",
                        "--binstubs=#{binstubs_path}",
                        *opts)
                if !result
                    STDERR.puts "FATAL: failed to install autoproj in #{dot_autoproj}"
                    exit 1
                end

                # Now tune the binstubs to force the usage of the autoproj
                # gemfile. Otherwise, they get BUNDLE_GEMFILE from the
                # environment by default
                Dir.glob(File.join(binstubs_path, '*')) do |path|
                    next if !File.file?(path)
                    # Do NOT do that for bundler, otherwise it will fail with an
                    # "already loaded gemfile" message once we e.g. try to do
                    # 'bundler install --gemfile=NEW_GEMFILE'
                    next if File.basename(path) == 'bundler'

                    lines = File.readlines(path)
                    filtered = lines.map { |l| l.gsub(/^(\s*ENV\[['"]BUNDLE_GEMFILE['"]\]\s*)\|\|=/, '\\1=') }
                    if lines == filtered
                        raise UnexpectedBinstub, "expected #{path} to contain a line looking like ENV['BUNDLE_GEMFILE'] ||= but could not find one"
                    end
                    File.open(path, 'w') do |io|
                        io.write filtered.join("")
                    end
                end

                env['PATH'] << File.join(autoproj_install_dir, 'bin')
                if private_autoproj?
                    env['GEM_PATH'] << autoproj_install_dir
                end
            end

            def update_configuration
                if File.exist?(autoproj_config_path)
                    config = YAML.load(File.read(autoproj_config_path)) || Hash.new
                else
                    config = Hash.new
                end
                config['private_bundler']  = private_bundler?
                config['private_autoproj'] = private_autoproj?
                config['private_gems']     = private_gems?
                File.open(autoproj_config_path, 'w') do |io|
                    YAML.dump(config, io)
                end
            end

            def find_in_clean_path(command)
                clean_path = env_for_child['PATH'].split(File::PATH_SEPARATOR)
                clean_path.each do |p|
                    full_path = File.join(p, command)
                    if File.file?(full_path)
                        return full_path
                    end
                end
                nil
            end

            def find_bundler
                clean_env = env_for_child
                Gem.paths = Hash[
                    'GEM_HOME' => clean_env['GEM_HOME'] || Gem.default_dir,
                    'GEM_PATH' => clean_env['GEM_PATH'] || nil
                ]
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
                bindir = IO.popen(clean_env, [Gem.ruby, '-e', 'puts Gem.bindir']).read
                if bindir
                    env['PATH'].unshift bindir.chomp
                else
                    STDERR.puts "FATAL: cannot run #{Gem.ruby} -e 'puts Gem.bindir'"
                    exit 1
                end

                bundler = find_in_clean_path('bundler')
                if !bundler
                    clean_path = env_for_child['PATH']
                    STDERR.puts "FATAL: cannot find 'bundler' in PATH=#{clean_path}"
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
                bundler
            end

            def install
                if private_bundler?
                    puts "Installing bundler in #{bundler_install_dir}"
                    bundler = install_bundler
                else
                    bundler = find_bundler
                    puts "Detected bundler at #{bundler}"
                end
                save_gemfile
                puts "Installing autoproj in #{dot_autoproj}"
                install_autoproj(bundler)
            end

            # Actually perform the install
            def run(stage2: false)
                if stage2
                    require 'autobuild'
                    save_env_sh
                else
                    install

                    env_for_child.each do |k, v|
                        if v
                            ENV[k] = v
                        else
                            ENV.delete(k)
                        end
                    end
                    ENV['BUNDLE_GEMFILE'] = autoproj_gemfile_path
                    update_configuration
                    exec Gem.ruby, File.join(autoproj_install_dir, 'bin', 'autoproj'),
                        'install-stage2', root_dir
                end
            end
        end
    end
end

