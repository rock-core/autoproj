require "bundler/gem_tasks"
require "rake/testtask"

task 'default'
task 'gem' => 'build'

Rake::TestTask.new(:test) do |t|
    t.libs << "lib" << Dir.pwd
    t.test_files = FileList['test/**/test_*.rb']
end

desc "generate the bootstrap script"
task 'bootstrap' do
    require 'yaml'
    build_option_code = File.read(File.join(Dir.pwd, 'lib', 'autoproj', 'build_option.rb'))
    config_code = File.read(File.join(Dir.pwd, 'lib', 'autoproj', 'configuration.rb'))
    osdeps_code = File.read(File.join(Dir.pwd, 'lib', 'autoproj', 'osdeps.rb'))
    system_code = File.read(File.join(Dir.pwd, 'lib', 'autoproj', 'system.rb'))
    osdeps_defaults = File.read(File.join(Dir.pwd, 'lib', 'autoproj', 'default.osdeps'))
    require 'autobuild'
    tools_code = File.read(File.join(Autobuild::LIB_DIR, 'autobuild', 'tools.rb'))
    # Filter rubygems dependencies from the OSdeps default. They will be
    # installed at first build
    osdeps = YAML.load(osdeps_defaults)
    osdeps.delete_if do |name, content|
        if content.respond_to?(:delete)
            content.delete('gem')
            content.empty?
        else
            content == 'gem'
        end
    end
    osdeps_defaults = YAML.dump(osdeps)
    # Since we are using gsub to replace the content in the bootstrap file,
    # we have to quote all \
    [osdeps_code, system_code, osdeps_defaults, tools_code].each do |text|
        text.gsub! /\\/, '\\\\\\\\'
    end

    bootstrap_code = File.read(File.join(Dir.pwd, 'bin', 'autoproj_bootstrap.in')).
        gsub('BUILD_OPTION_CODE', build_option_code).
        gsub('CONFIG_CODE', config_code).
        gsub('OSDEPS_CODE', osdeps_code).
        gsub('SYSTEM_CODE', system_code).
        gsub('OSDEPS_DEFAULTS', osdeps_defaults).
        gsub('TOOLS_CODE', tools_code)
    File.open(File.join(Dir.pwd, 'bin', 'autoproj_bootstrap'), 'w') do |io|
        io.write bootstrap_code
    end
end
file 'bin/autoproj_bootstrap' => 'bootstrap'

