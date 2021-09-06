require "autoproj/test"

module Autoproj
    describe VCSDefinition do
        describe ".normalize_vcs_hash" do
            attr_reader :root_dir

            before do
                @root_dir = make_tmpdir
            end
            after do
                Autoproj.remove_source_handler "custom_handler"
            end

            it "interprets the type:url shortcut" do
                vcs = VCSDefinition.normalize_vcs_hash("git:git@github.com")
                assert_equal Hash[type: "git", url: "git@github.com"], vcs
            end

            it "normalizes the standard format" do
                vcs = VCSDefinition.normalize_vcs_hash("type" => "git", "url" => "u", "branch" => "b")
                assert_equal Hash[type: "git", url: "u", branch: "b"], vcs
            end

            it "resolves a local path relative to the config dir" do
                FileUtils.mkdir_p(dir = File.join(root_dir, "dir"))
                vcs = VCSDefinition.normalize_vcs_hash("dir", base_dir: root_dir)
                assert_equal Hash[type: "local", url: dir], vcs
            end
            it "resolves a local package set given in absolute" do
                FileUtils.mkdir_p(dir = File.join(root_dir, "dir"))
                vcs = VCSDefinition.normalize_vcs_hash(dir)
                assert_equal Hash[type: "local", url: dir], vcs
            end
            it "raises if given a relative path and no base_dir" do
                FileUtils.mkdir_p(File.join(root_dir, "dir"))
                e = assert_raises(ArgumentError) do
                    VCSDefinition.normalize_vcs_hash("dir")
                end
                assert_equal "VCS path 'dir' is relative and no base_dir was given",
                             e.message
            end
            it "raises if given a relative path that does not exist" do
                e = assert_raises(ArgumentError) do
                    VCSDefinition.normalize_vcs_hash("dir", base_dir: root_dir)
                end
                assert_equal "'dir' is neither a remote source specification, nor an existing local directory",
                             e.message
            end
            it "raises if given a full path that does not exist" do
                e = assert_raises(ArgumentError) do
                    VCSDefinition.normalize_vcs_hash("/full/dir", base_dir: root_dir)
                end
                assert_equal "'/full/dir' is neither a remote source specification, nor an existing local directory",
                             e.message
            end

            it "expands a source handler when the specification is a single string" do
                Autoproj.add_source_handler "custom_handler" do |url, options|
                    Hash[url: url, type: "local"].merge(options)
                end
                vcs = VCSDefinition.normalize_vcs_hash("custom_handler:test")
                assert_equal Hash[url: "test", type: "local"], vcs
            end

            it "expands a source handler when embedded in a normal VCS definition hash" do
                Autoproj.add_source_handler "custom_handler" do |url, options|
                    Hash[url: url, type: "local"].merge(options)
                end
                vcs = VCSDefinition.normalize_vcs_hash(Hash["custom_handler" => "test", "other" => "option"])
                assert_equal Hash[url: "test", type: "local", other: "option"], vcs
            end
        end

        describe ".from_raw" do
            it "raises if the VCS has no type" do
                e = assert_raises(ArgumentError) do
                    VCSDefinition.from_raw(url: "test")
                end
                assert_equal "the source specification { url: test } normalizes into { url: test }, which does not have a VCS type",
                             e.message
            end
            it "raises if the VCS has no URL and type is not 'none'" do
                assert_raises(ArgumentError) do
                    VCSDefinition.from_raw(type: "local")
                end
            end
            it "passes if the VCS type is none and there is no URL" do
                assert_raises(ArgumentError) do
                    VCSDefinition.from_raw(type: "local")
                end
            end
        end

        describe "#create_autobuild_importer" do
            it "does not create an importer if type is none" do
                vcs = Autoproj::VCSDefinition.from_raw({ type: "none", url: nil })
                assert !vcs.create_autobuild_importer
            end
            it "does not create an importer if type is local" do
                vcs = Autoproj::VCSDefinition.from_raw({ type: "local", url: "/test" })
                assert !vcs.create_autobuild_importer
            end
            it "creates an importer of the required type and options" do
                vcs = Autoproj::VCSDefinition.from_raw(
                    { type: "git", url: "https://github.com" }
                )
                importer = vcs.create_autobuild_importer
                assert_kind_of Autobuild::Git, importer
                assert_equal "https://github.com", importer.repository
            end
            it "registers the various versions of the history if the importer supports declare_alternate_repository" do
                ws_create
                base_package_set = ws_define_package_set "base"
                base_vcs = Autoproj::VCSDefinition.from_raw(Hash[type: "git", url: "https://github.com"], from: base_package_set)
                override_package_set = ws_define_package_set "override"
                override_vcs = base_vcs.update(Hash[url: "https://github.com/fork"], from: override_package_set)
                importer = override_vcs.create_autobuild_importer
                assert_equal [["base", "https://github.com", "https://github.com"],
                              ["override", "https://github.com/fork", "https://github.com/fork"]], importer.additional_remotes
            end
        end

        describe "custom source handlers" do
            after do
                Autoproj.remove_source_handler "custom_handler"
            end
            it "adds one" do
                recorder = flexmock
                recorder.should_receive(:called).with("url", expected_options = {})
                        .once
                ret = flexmock
                Autoproj.add_source_handler "custom_handler" do |url, **options|
                    recorder.called(url, options)
                    ret
                end
                assert Autoproj.has_source_handler?("custom_handler")
                assert_equal ret, Autoproj.call_source_handler("custom_handler", "url", expected_options)
            end
            it "raises ArgumentError if attempting to call a handler that does not exist" do
                refute Autoproj.has_source_handler?("custom_handler")
                e = assert_raises(ArgumentError) do
                    Autoproj.call_source_handler("custom_handler", flexmock, flexmock)
                end
                assert_equal "there is no source handler for custom_handler", e.message
            end

            it "removes one" do
                Autoproj.add_source_handler "custom_handler" do |url, options|
                end
                Autoproj.remove_source_handler "custom_handler"
                refute Autoproj.has_source_handler?("custom_handler")
                assert_raises(ArgumentError) do
                    Autoproj.call_source_handler("custom_handler", flexmock, flexmock)
                end
            end
        end

        describe "#==" do
            it "returns false if given an arbitrary object" do
                refute_equal Object.new, VCSDefinition.none
            end

            describe "null definitions" do
                attr_reader :left

                before do
                    @left = VCSDefinition.none
                end

                it "ignores all options for null definitions" do
                    left.options[:garbage] = true
                    right = VCSDefinition.none
                    left.options[:garbage] = false
                    assert_equal left, right
                end

                it "returns false for non-null definitions" do
                    right = VCSDefinition.from_raw(type: "local", url: "/path/to/somewhere/else", garbage_option: false)
                    refute_equal left, right
                end
            end

            describe "a local vcs receiver" do
                attr_reader :left

                before do
                    @left = VCSDefinition.from_raw(type: "local", url: "/path/to", garbage_option: true)
                end

                it "only compares against the URL for local VCS" do
                    right = VCSDefinition.from_raw(type: "local", url: "/path/to", garbage_option: false)
                    assert_equal left, right
                    right = VCSDefinition.from_raw(type: "local", url: "/path/to/somewhere/else", garbage_option: false)
                    refute_equal left, right
                end
                it "returns false for non-local VCSes even if they have the same URL" do
                    right = VCSDefinition.from_raw(type: "git", url: "/path/to", garbage_option: false)
                    refute_equal left, right
                end
            end

            describe "an non-local, non-null definition" do
                attr_reader :left

                before do
                    @left = VCSDefinition.from_raw(type: "git", url: "/path/to", branch: "master")
                end

                it "returns false for a null VCS" do
                    refute_equal left, VCSDefinition.none
                end
                it "returns false for a local VCS" do
                    refute_equal left, VCSDefinition.from_raw(type: "local", url: "/path/to")
                end
                it "delegates to the autobuild importer's #source_id implementation" do
                    flexmock(left).should_receive(:create_autobuild_importer)
                                  .and_return(flexmock(source_id: (source_id = flexmock)))

                    right = VCSDefinition.from_raw(type: "git", url: "/path/to", branch: "arbitrary")
                    flexmock(right).should_receive(:create_autobuild_importer)
                                   .and_return(flexmock(source_id: source_id))
                    assert_equal left, right

                    right = VCSDefinition.from_raw(type: "git", url: "/path/to", branch: "arbitrary")
                    flexmock(right).should_receive(:create_autobuild_importer)
                                   .and_return(flexmock(source_id: flexmock))
                    refute_equal left, right
                end
            end
        end

        describe ".to_absolute_url" do
            it "keeps absolute paths unchanged" do
                assert_equal "/absolute/path", VCSDefinition.to_absolute_url("/absolute/path", flexmock)
            end
            it "keeps well-formed URIs unchanged" do
                assert_equal "https://absolute/path", VCSDefinition.to_absolute_url("https://absolute/path", flexmock)
            end
            it "keeps git-like URIs unchanged" do
                assert_equal "git@github.com:path", VCSDefinition.to_absolute_url("git@github.com:path", flexmock)
            end
            it "keeps svn-like URIs unchanged" do
                assert_equal "svn+ssh://path", VCSDefinition.to_absolute_url("svn+ssh://path", flexmock)
            end
            it "resolves relative paths w.r.t. the given root dir" do
                assert_equal "/absolute/path", VCSDefinition.to_absolute_url("path", "/absolute")
            end
        end
    end
end
