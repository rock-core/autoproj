require "bundler/gem_tasks"
require "rake/testtask"

task "default"
task "gem" => "build"

Rake::TestTask.new(:test) do |t|
    t.libs << "lib" << Dir.pwd
    t.test_files = FileList["test/**/test_*.rb"]
end

desc "generate the bootstrap script"
task "bootstrap" do
    require "yaml"
    autoproj_ops_install = File.read(File.join(Dir.pwd, "lib", "autoproj", "ops", "install.rb"))
    # Since we are using gsub to replace the content in the bootstrap file,
    # we have to quote all \
    autoproj_ops_install.gsub!(/\\/, "\\\\\\\\")

    %w[bootstrap install].each do |install_script|
        bootstrap_code = File.read(File.join(Dir.pwd, "bin", "autoproj_#{install_script}.in"))
                             .gsub("require 'autoproj/ops/install'", autoproj_ops_install)
        File.open(File.join(Dir.pwd, "bin", "autoproj_#{install_script}"), "w") do |io|
            io.write bootstrap_code
        end
    end
end

require "autoproj/bash_completion"
require "autoproj/zsh_completion"

shells = [["bash", Autoproj::BashCompletion], ["zsh", Autoproj::ZshCompletion]]
clis = [%w[alocate locate], %w[alog log], %w[amake build], %w[aup update],
        ["autoproj", nil]]

shell_dir = File.join(Dir.pwd, "shell")
completion_dir = File.join(shell_dir, "completion")

desc "generate the shell helpers scripts"
task "helpers" do
    require "erb"
    templates_dir = File.join(Dir.pwd, "lib", "autoproj", "templates")
    FileUtils.mkdir_p(completion_dir)

    shells.each do |shell|
        clis.each do |cli|
            completion = shell[1].new(cli[0], command: cli[1])
            completion_file = File.join(completion_dir, "#{cli[0]}_#{shell[0]}")

            IO.write(completion_file, completion.generate)
        end
        erb = File.read(File.join(templates_dir, "helpers.#{shell[0]}.erb"))
        helper_file = File.join(shell_dir, "autoproj_#{shell[0]}")

        IO.write(helper_file, ::ERB.new(erb, nil, "-").result(binding))
    end
end

file "bin/autoproj_bootstrap" => "bootstrap"
