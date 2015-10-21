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
    autoproj_ops_install = File.read(File.join(Dir.pwd, 'lib', 'autoproj', 'ops', 'install.rb'))
    # Since we are using gsub to replace the content in the bootstrap file,
    # we have to quote all \
    autoproj_ops_install.gsub! /\\/, '\\\\\\\\'

    %w{bootstrap install}.each do |install_script|
        bootstrap_code = File.read(File.join(Dir.pwd, 'bin', "autoproj_#{install_script}.in")).
            gsub('AUTOPROJ_OPS_INSTALL', autoproj_ops_install)
        File.open(File.join(Dir.pwd, 'bin', "autoproj_#{install_script}"), 'w') do |io|
            io.write bootstrap_code
        end
    end
end
file 'bin/autoproj_bootstrap' => 'bootstrap'

