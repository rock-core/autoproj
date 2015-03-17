require 'autoproj/test'
require 'autoproj/autobuild'

describe Autobuild::Package do
    describe "#remove_dependency" do
        attr_reader :pkg
        before do
            @pkg = Autobuild.import('pkg')
            Autobuild.import('dep')
        end

        it "removes direct dependencies" do
            pkg.dependencies << 'dep'
            pkg.remove_dependency 'dep'
            assert !pkg.dependencies.include?('dep')
        end

        it "removes optional dependencies" do
            pkg.optional_dependency 'dep'
            pkg.remove_dependency 'dep'
            assert !pkg.optional_dependencies.include?('dep')
        end

        it "removes OS dependencies" do
            pkg.os_packages << 'dep'
            pkg.remove_dependency 'dep'
            assert !pkg.os_packages.include?('dep')
        end
    end
end
