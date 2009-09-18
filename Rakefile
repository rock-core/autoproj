$LOAD_PATH.unshift File.join(Dir.pwd, 'lib')
require 'rubotics/system'

namespace 'pkg' do
    all_gems = []
    Dir.glob(File.join('packages', 'source', 'gem', '*.gemspec')) do |file|
        file = File.expand_path(file)
        generated_gem = File.join('packages', File.basename(file))
        all_gems << generated_gem
        task generated_gem => file do
            Dir.chdir 'packages' do
                Rubotics.run_as_user 'gem', 'build', file
            end
        end
    end

    task 'update' => all_gems
end

