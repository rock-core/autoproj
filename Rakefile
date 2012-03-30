require 'utilrb/rake_common'
$LOAD_PATH.unshift File.join(Dir.pwd, 'lib')

task 'default'
Utilrb::Rake.hoe do
    namespace 'dist' do
        Hoe.spec 'autoproj' do
            self.developer "Sylvain Joyeux", "sylvain.joyeux@dfki.de"

            self.url = ["http://rock-robotics.org/documentation/autoproj",
                "git://github.com/doudou/autoproj.git"]
            self.rubyforge_name = 'autobuild'
            self.summary = 'Easy installation and management of software packages'
            self.description = paragraphs_of('README.txt', 0..1).join("\n\n")
            self.changes     = paragraphs_of('History.txt', 0..1).join("\n\n")

            extra_deps << 
                ['autobuild',   '>= 1.5.57'] <<
                ['utilrb', '>= 1.3.3'] <<
                ['highline', '>= 1.5.0']
        end
    end
end

namespace 'dist' do
    desc "generate the bootstrap script"
    task 'bootstrap' do
        require 'yaml'
        osdeps_code = File.read(File.join(Dir.pwd, 'lib', 'autoproj', 'osdeps.rb'))
        options_code = File.read(File.join(Dir.pwd, 'lib', 'autoproj', 'options.rb'))
        system_code = File.read(File.join(Dir.pwd, 'lib', 'autoproj', 'system.rb'))
        osdeps_defaults = File.read(File.join(Dir.pwd, 'lib', 'autoproj', 'default.osdeps'))
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

        bootstrap_code = File.read(File.join(Dir.pwd, 'bin', 'autoproj_bootstrap.in')).
            gsub('OSDEPS_CODE', osdeps_code).
            gsub('OPTIONS_CODE', options_code).
            gsub('SYSTEM_CODE', system_code).
            gsub('OSDEPS_DEFAULTS', osdeps_defaults)
        File.open(File.join(Dir.pwd, 'bin', 'autoproj_bootstrap'), 'w') do |io|
            io.write bootstrap_code
        end
    end
end
file 'bin/autoproj_bootstrap' => 'dist:bootstrap'

Utilrb::Rake.rdoc do
    task 'doc' => 'doc:all'
    task 'clobber_docs' => 'doc:clobber'
    task 'redocs' do
        Rake::Task['doc:clobber'].invoke
        Rake::Task['doc'].invoke
    end

    namespace 'doc' do
        task 'all' => %w{api}
        task 'clobber' => 'clobber_api'
        RDoc::Task.new("api") do |rdoc|
            rdoc.rdoc_dir = 'doc'
            rdoc.title    = "autoproj"
            rdoc.options << '--show-hash'
            rdoc.rdoc_files.include('lib/**/*.rb')
        end
    end
end


