require 'autoproj/test'
require 'fakefs/safe'

describe Autoproj::VCSDefinition do
    describe ".vcs_definition_to_hash" do
        before do
            FakeFS.activate!
        end

        after do
            FakeFS.deactivate!
            FakeFS::FileSystem.clear
        end

        it "interprets plain strings as local directories" do
            FileUtils.mkdir_p '/test'
            vcs = Autoproj::VCSDefinition.from_raw('/test')
            assert vcs.local?
            assert_equal '/test', vcs.url
        end

        it "interprets the type:url shortcut" do
            vcs = Autoproj::VCSDefinition.from_raw('git:git@github.com')
            assert_equal 'git', vcs.type
            assert_equal 'git@github.com', vcs.url
        end

        it "normalizes the standard format" do
            vcs = Autoproj::VCSDefinition.from_raw(Hash['type' => 'git', 'url' => 'u', 'branch' => 'b'])
            assert_equal 'git', vcs.type
            assert_equal 'u', vcs.url
            assert_equal 'b', vcs.options[:branch]
        end
    end

    describe "#create_autobuild_importer" do
        it "does not create an importer if type is none" do
            vcs = Autoproj::VCSDefinition.from_raw(type: 'none', url: nil)
            assert !vcs.create_autobuild_importer
        end
        it "does not create an importer if type is local" do
            vcs = Autoproj::VCSDefinition.from_raw(type: 'local', url: '/test')
            assert !vcs.create_autobuild_importer
        end
    end
end
