require 'autoproj/test'

module Autoproj
    describe VCSDefinition do
        describe ".normalize_vcs_hash" do
            attr_reader :root_dir
            before do
                @root_dir = make_tmpdir
            end
            after do
                Autoproj.remove_source_handler 'custom_handler'
            end

            it "interprets the type:url shortcut" do
                vcs = VCSDefinition.normalize_vcs_hash('git:git@github.com')
                assert_equal Hash[type: 'git', url: 'git@github.com'], vcs
            end

            it "normalizes the standard format" do
                vcs = VCSDefinition.normalize_vcs_hash('type' => 'git', 'url' => 'u', 'branch' => 'b')
                assert_equal Hash[type: 'git', url: 'u', branch: 'b'], vcs
            end

            it "resolves a local path relative to the config dir" do
                FileUtils.mkdir_p(dir = File.join(root_dir, 'dir'))
                vcs = VCSDefinition.normalize_vcs_hash('dir', base_dir: root_dir)
                assert_equal Hash[type: 'local', url: dir], vcs
            end
            it "resolves a local package set given in absolute" do
                FileUtils.mkdir_p(dir = File.join(root_dir, 'dir'))
                vcs = VCSDefinition.normalize_vcs_hash(dir)
                assert_equal Hash[type: 'local', url: dir], vcs
            end
            it "raises if given a relative path and no base_dir" do
                FileUtils.mkdir_p(dir = File.join(root_dir, 'dir'))
                e = assert_raises(ArgumentError) do
                    VCSDefinition.normalize_vcs_hash('dir')
                end
                assert_equal "VCS path 'dir' is relative and no base_dir was given",
                    e.message
            end
            it "raises if given a relative path that does not exist" do
                e = assert_raises(ArgumentError) do
                    VCSDefinition.normalize_vcs_hash('dir', base_dir: root_dir)
                end
                assert_equal "'dir' is neither a remote source specification, nor an existing local directory",
                    e.message
            end
            it "raises if given a full path that does not exist" do
                e = assert_raises(ArgumentError) do
                    VCSDefinition.normalize_vcs_hash('/full/dir', base_dir: root_dir)
                end
                assert_equal "'/full/dir' is neither a remote source specification, nor an existing local directory",
                    e.message
            end

            it "expands a source handler when the specification is a single string" do
                Autoproj.add_source_handler 'custom_handler' do |url, options|
                    Hash[url: url, type: 'local'].merge(options)
                end
                vcs = VCSDefinition.normalize_vcs_hash('custom_handler:test')
                assert_equal Hash[url: 'test', type: 'local'], vcs
            end

            it "expands a source handler when embedded in a normal VCS definition hash" do
                Autoproj.add_source_handler 'custom_handler' do |url, options|
                    Hash[url: url, type: 'local'].merge(options)
                end
                vcs = VCSDefinition.normalize_vcs_hash(Hash['custom_handler' => 'test', 'other' => 'option'])
                assert_equal Hash[url: 'test', type: 'local', other: 'option'], vcs
            end
        end

        describe ".from_raw" do
            it "raises if the VCS has no type" do
                e = assert_raises(ArgumentError) do
                    VCSDefinition.from_raw(url: 'test')
                end
                assert_equal  "the source specification { url: test } normalizes into { url: test }, which does not have a VCS type",
                    e.message
            end
            it "raises if the VCS has no URL and type is not 'none'" do
                e = assert_raises(ArgumentError) do
                    VCSDefinition.from_raw(type: 'local')
                end
            end
            it "passes if the VCS type is none and there is no URL" do
                e = assert_raises(ArgumentError) do
                    VCSDefinition.from_raw(type: 'local')
                end
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

        describe "custom source handlers" do
            after do
                Autoproj.remove_source_handler 'custom_handler'
            end
            it "adds one" do
                recorder = flexmock
                recorder.should_receive(:called).with('url', options = flexmock).
                    once
                ret = flexmock
                Autoproj.add_source_handler 'custom_handler' do |url, options|
                    recorder.called(url, options)
                    ret
                end
                assert Autoproj.has_source_handler?('custom_handler')
                assert_equal ret, Autoproj.call_source_handler('custom_handler', 'url', options)
            end 
            it "raises ArgumentError if attempting to call a handler that does not exist" do
                refute Autoproj.has_source_handler?('custom_handler')
                e = assert_raises(ArgumentError) do
                    Autoproj.call_source_handler('custom_handler', flexmock, flexmock)
                end
                assert_equal "there is no source handler for custom_handler", e.message
            end

            it "removes one" do
                Autoproj.add_source_handler 'custom_handler' do |url, options|
                end
                Autoproj.remove_source_handler 'custom_handler'
                refute Autoproj.has_source_handler?('custom_handler')
                assert_raises(ArgumentError) do
                    Autoproj.call_source_handler('custom_handler', flexmock, flexmock)
                end
            end 
        end
    end
end
