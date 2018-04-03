require 'autoproj/test'

module Autoproj
    describe PackageManifest do
        attr_reader :pkg

        before do
            @pkg = flexmock(name: 'test')
        end

        it "raises a PackageException if the manifest is invalid" do
            e = assert_raises(Autobuild::PackageException) do
                Autoproj::PackageManifest.parse(pkg, "<package")
            end
            assert_equal 'test', e.target # the package name
        end

        it "is not null by default" do
            refute PackageManifest.new(pkg).null?
        end

        it "creates a null manifest with PackageManifest.null(pkg)" do
            assert PackageManifest.null(pkg).null?
        end

        it "is null if explicitely defined so" do
            assert PackageManifest.new(pkg, null: true).null?
        end

        describe "deprecated methods" do
            attr_reader :manifest
            before do
                @manifest = PackageManifest.new(pkg)
            end
            it "calls #each_dependency from #each_package_dependency" do
                block = Proc.new {}
                flexmock(manifest).should_receive(:each_dependency).once.
                    with(modes = flexmock, block)
                _, err = capture_deprecation_message do
                    manifest.each_package_dependency(modes, &block)
                end
                assert_match(/WARN: Autoproj::PackageManifest#each_package_dependency is deprecated, call #each_dependency instead/, err)
            end
            it "calls #each_dependency from #each_os_dependency" do
                block = Proc.new {}
                flexmock(manifest).should_receive(:each_dependency).once.
                    with(modes = flexmock, block)
                _, err = capture_deprecation_message do
                    manifest.each_os_dependency(modes, &block)
                end
                assert_match(/WARN: Autoproj::PackageManifest#each_os_dependency is deprecated, call #each_dependency instead/, err)
            end
        end

        describe "tags" do
            it "parses a single tags block" do
                manifest = Autoproj::PackageManifest.parse(pkg, "<package><tags>tag1,tag2</tags></package>")
                assert_equal %w{tag1 tag2}, manifest.tags
            end
            it "parses concatenates the content of multiple tags blocks" do
                manifest = Autoproj::PackageManifest.parse(pkg, "<package><tags>tag1,tag2</tags><tags>tag3</tags></package>")
                assert_equal %w{tag1 tag2 tag3}, manifest.tags
            end
        end

        describe "description and brief" do
            it "loads the content of the description block" do
                manifest = Autoproj::PackageManifest.parse(pkg, "<package><description>long\ndocumentation\nblock</description></package>")
                assert_equal "long\ndocumentation\nblock", manifest.documentation
            end
            it "returns the short documentation if there is no expanded documentation" do
                manifest = Autoproj::PackageManifest.parse(pkg, "<package><description brief=\"brief documentation\"/></package>")
                assert_equal "brief documentation", manifest.documentation
            end
            it "reports if there is no documentation" do
                manifest = Autoproj::PackageManifest.parse(pkg, "<package></package>")
                refute manifest.has_documentation?
            end
            it "reports if there is no documentation" do
                manifest = Autoproj::PackageManifest.parse(pkg, "<package><description/></package>")
                refute manifest.has_documentation?
            end
            it "interprets an empty documentation text as no documentation" do
                manifest = Autoproj::PackageManifest.parse(pkg, "<package><description>  \n  </description></package>")
                refute manifest.has_documentation?
            end
            it "returns a default string if there is no documentation at all" do
                manifest = Autoproj::PackageManifest.parse(pkg, "<package></package>")
                assert_equal "no documentation available for package 'test' in its manifest.xml file",
                    manifest.documentation
            end

            it "loads the content of the short documentation attribute" do
                manifest = Autoproj::PackageManifest.parse(pkg, "<package><description brief=\"brief documentation\"/></package>")
                assert_equal "brief documentation", manifest.short_documentation
            end
            it "returns a default string if there is no brief documentation" do
                manifest = Autoproj::PackageManifest.parse(pkg, "<package><documentation>long</documentation></package>")
                assert_equal "no documentation available for package 'test' in its manifest.xml file",
                    manifest.short_documentation
            end
            it "reports if there is no brief documentation" do
                manifest = Autoproj::PackageManifest.parse(pkg, "<package><documentation>long</documentation></package>")
                refute manifest.has_short_documentation?
            end
        end

        describe "dependencies" do
            def parse_dependency(xml)
                manifest = PackageManifest.parse(pkg, xml)
                assert_equal 1, manifest.dependencies.size
                manifest.dependencies.first
            end

            describe "<depend>" do
                it "raises if the tag has neither a name nor a package attribute" do
                    assert_raises(InvalidPackageManifest) do
                        PackageManifest.parse(pkg, "<package><depend/></package>")
                    end
                end
                it "parses the name attribute" do
                    dependency = parse_dependency("<package><depend name='test'/></package>")
                    assert_equal 'test', dependency.name
                end
                it "parses the package attribute" do
                    dependency = parse_dependency("<package><depend package='test'/></package>")
                    assert_equal 'test', dependency.name
                end
                it "has no modes by default" do
                    dependency = parse_dependency("<package><depend package='test'/></package>")
                    assert_equal [], dependency.modes
                end
                it "parses the modes attribute" do
                    dependency = parse_dependency("<package><depend package='test' modes='doc,test'/></package>")
                    assert_equal ['doc', 'test'], dependency.modes
                end
                it "handles an empty modes attribute" do
                    dependency = parse_dependency("<package><depend package='test' modes=''/></package>")
                    assert_equal [], dependency.modes
                end
                it "is not optional by default" do
                    dependency = parse_dependency("<package><depend package='test'/></package>")
                    refute dependency.optional
                end
                it "is not optional if the optional attribute is not 1" do
                    dependency = parse_dependency("<package><depend package='test' optional='0'/></package>")
                    refute dependency.optional
                end
                it "is optional if the optional attribute is 1" do
                    dependency = parse_dependency("<package><depend package='test' optional='1'/></package>")
                    assert dependency.optional
                end
            end

            describe "<depend_optional>" do
                it "raises if the tag has neither a name nor a package attribute" do
                    assert_raises(InvalidPackageManifest) do
                        PackageManifest.parse(pkg, "<package><depend_optional/></package>")
                    end
                end
                it "parses the name attribute" do
                    dependency = parse_dependency("<package><depend_optional name='test'/></package>")
                    assert_equal 'test', dependency.name
                end
                it "parses the package attribute" do
                    dependency = parse_dependency("<package><depend_optional package='test'/></package>")
                    assert_equal 'test', dependency.name
                end
                it "is optional by default" do
                    dependency = parse_dependency("<package><depend_optional package='test'/></package>")
                    assert dependency.optional
                end
                it "has no modes by default" do
                    dependency = parse_dependency("<package><depend_optional package='test'/></package>")
                    assert_equal [], dependency.modes
                end
                it "handles an empty modes attribute" do
                    dependency = parse_dependency("<package><depend_optional package='test' modes=''/></package>")
                    assert_equal [], dependency.modes
                end
                it "parses a depend_optional tag modes attribute" do
                    dependency = parse_dependency("<package><depend_optional package='test' modes='doc,test'/></package>")
                    assert_equal ['doc', 'test'], dependency.modes
                end
            end

            describe "<$MODE_depend>" do
                it "raises if the tag has neither a name nor a package attribute" do
                    assert_raises(InvalidPackageManifest) do
                        PackageManifest.parse(pkg, "<package><doc_depend/></package>")
                    end
                end
                it "parses the name attribute" do
                    dependency = parse_dependency("<package><doc_depend name='test'/></package>")
                    assert_equal 'test', dependency.name
                end
                it "parses the package attribute" do
                    dependency = parse_dependency("<package><doc_depend package='test'/></package>")
                    assert_equal 'test', dependency.name
                end
                it "has the tag's mode by default" do
                    dependency = parse_dependency("<package><doc_depend package='test'/></package>")
                    assert_equal ['doc'], dependency.modes
                end
                it "adds the values of the 'modes' attribute" do
                    dependency = parse_dependency("<package><doc_depend package='test' modes='test'/></package>")
                    assert_equal ['doc', 'test'], dependency.modes
                end
                it "handles an empty modes attribute" do
                    dependency = parse_dependency("<package><doc_depend package='test' modes=''/></package>")
                    assert_equal ['doc'], dependency.modes
                end
                it "is not optional by default" do
                    dependency = parse_dependency("<package><doc_depend package='test'/></package>")
                    refute dependency.optional
                end
                it "is not optional if the optional attribute is not 1" do
                    dependency = parse_dependency("<package><doc_depend package='test' optional='0'/></package>")
                    refute dependency.optional
                end
                it "is optional if the optional attribute is 1" do
                    dependency = parse_dependency("<package><doc_depend package='test' optional='1'/></package>")
                    assert dependency.optional
                end
            end

            describe "<rosdep>" do
                it "raises if the tag has neither a name nor a package attribute" do
                    assert_raises(InvalidPackageManifest) do
                        PackageManifest.parse(pkg, "<rosdep><rosdep/></package>")
                    end
                end
                it "parses the name attribute" do
                    dependency = parse_dependency("<package><rosdep name='test'/></package>")
                    assert_equal 'test', dependency.name
                end
                it "parses the package attribute" do
                    dependency = parse_dependency("<package><rosdep package='test'/></package>")
                    assert_equal 'test', dependency.name
                end
                it "has no modes by default" do
                    dependency = parse_dependency("<package><rosdep package='test'/></package>")
                    assert_equal [], dependency.modes
                end
                it "parses the modes attribute" do
                    dependency = parse_dependency("<package><rosdep package='test' modes='doc,test'/></package>")
                    assert_equal ['doc', 'test'], dependency.modes
                end
                it "handles an empty modes attribute" do
                    dependency = parse_dependency("<package><rosdep package='test' modes=''/></package>")
                    assert_equal [], dependency.modes
                end
                it "is not optional by default" do
                    dependency = parse_dependency("<package><rosdep package='test'/></package>")
                    refute dependency.optional
                end
                it "is not optional if the optional attribute is not 1" do
                    dependency = parse_dependency("<package><rosdep package='test' optional='0'/></package>")
                    refute dependency.optional
                end
                it "is optional if the optional attribute is 1" do
                    dependency = parse_dependency("<package><rosdep package='test' optional='1'/></package>")
                    assert dependency.optional
                end
            end
        end

        describe "authors" do
            it "parses the author tag" do
                manifest = PackageManifest.parse(pkg, '<package><author>Firstname Lastname/name@domain</author><author>Author2/author2@domain</author></package>')
                assert_equal [PackageManifest::ContactInfo.new('Firstname Lastname', 'name@domain'),
                              PackageManifest::ContactInfo.new('Author2', 'author2@domain')], manifest.authors
            end
            it "yields the author names and emails" do
                manifest = PackageManifest.new(pkg)
                manifest.authors << PackageManifest::ContactInfo.new('name', 'email')
                assert_equal [['name', 'email']], manifest.each_author.to_a
            end
        end

        describe "maintainers" do
            it "parses the maintainer tag" do
                manifest = PackageManifest.parse(pkg, '<package><maintainer>Firstname Lastname/name@domain</maintainer><maintainer>Author2/author2@domain</maintainer></package>')
                assert_equal [PackageManifest::ContactInfo.new('Firstname Lastname', 'name@domain'),
                              PackageManifest::ContactInfo.new('Author2', 'author2@domain')], manifest.maintainers
            end
            it "yields the maintainer names and emails" do
                manifest = PackageManifest.new(pkg)
                manifest.maintainers << PackageManifest::ContactInfo.new('name', 'email')
                assert_equal [['name', 'email']], manifest.each_maintainer.to_a
            end
        end

        describe "#each_rock_maintainer" do
            it "parses the rock_maintainer tag" do
                manifest = PackageManifest.parse(pkg, '<package><rock_maintainer>Firstname Lastname/name@domain</rock_maintainer><rock_maintainer>Author2/author2@domain</rock_maintainer></package>')
                assert_equal [PackageManifest::ContactInfo.new('Firstname Lastname', 'name@domain'),
                              PackageManifest::ContactInfo.new('Author2', 'author2@domain')], manifest.rock_maintainers
            end
            it "yields the rock maintainer names and emails" do
                manifest = PackageManifest.new(pkg)
                manifest.rock_maintainers << PackageManifest::ContactInfo.new('name', 'email')
                assert_equal [['name', 'email']], manifest.each_rock_maintainer.to_a
            end
        end

        describe "#each_dependency" do
            attr_reader :manifest
            before do
                @manifest = PackageManifest.new(pkg)
            end
            it "yields the dependency names and optional attribute" do
                manifest.add_dependency 'mandatory'
                manifest.add_dependency 'optional', optional: true
                assert_equal Set[['mandatory', false], ['optional', true]],
                    manifest.each_dependency.to_set
            end
            it "does not yield dependencies restricted to certain modes if the mode is not provided" do
                manifest.add_dependency 'test', modes: ['doc']
                assert_equal Set[],
                    manifest.each_dependency.to_set
            end
            it "does yield dependencies that have no mode restriction a mode is provided" do
                manifest.add_dependency 'general'
                manifest.add_dependency 'doc', modes: ['doc']
                assert_equal Set[['general', false], ['doc', false]],
                    manifest.each_dependency(['doc']).to_set
            end
            it "does yield dependencies restricted to certain modes if the mode is provided" do
                manifest.add_dependency 'test', modes: ['test']
                manifest.add_dependency 'doc_and_test', modes: ['doc', 'test']
                assert_equal Set[['test', false], ['doc_and_test', false]],
                    manifest.each_dependency(['test']).to_set
            end
        end

        describe "ros manifest" do
            def subject_parse(text)
                Autoproj::PackageManifest.parse(pkg, text, loader_class: Autoproj::PackageManifest::RosLoader)
            end

            describe "description" do
                it "loads the content of the description block" do
                    manifest = subject_parse("<package><description>long\ndocumentation\nblock</description></package>")
                    assert_equal "long\ndocumentation\nblock", manifest.documentation
                end
                it "allows html tags in a long description block" do
                    manifest = subject_parse("<package><description>long <tt>test</tt> documentation block</description></package>")
                    assert_equal "long test documentation block", manifest.documentation
                end
                it "reports if there is no documentation" do
                    manifest = subject_parse("<package></package>")
                    refute manifest.has_documentation?
                end
                it "reports if there is no documentation" do
                    manifest = subject_parse("<package><description/></package>")
                    refute manifest.has_documentation?
                end
                it "interprets an empty documentation text as no documentation" do
                    manifest = subject_parse("<package><description>  \n  </description></package>")
                    refute manifest.has_documentation?
                end
                it "returns a default string if there is no documentation at all" do
                    manifest = subject_parse("<package></package>")
                    assert_equal "no documentation available for package 'test' in its manifest.xml file",
                        manifest.documentation
                end
                it "returns a default string if there is no brief documentation" do
                    manifest = subject_parse("<package><documentation>long</documentation></package>")
                    assert_equal "no documentation available for package 'test' in its manifest.xml file",
                        manifest.short_documentation
                end
                it "reports if there is no brief documentation" do
                    manifest = subject_parse("<package><documentation>long</documentation></package>")
                    refute manifest.has_short_documentation?
                end
            end

            describe "dependencies" do
                def parse_dependency(xml)
                    loader_class = Autoproj::PackageManifest::RosLoader
                    manifest = PackageManifest.parse(pkg, xml, loader_class: loader_class)
                    assert_equal 1, manifest.dependencies.size
                    manifest.dependencies.first
                end

                Autoproj::PackageManifest::RosLoader::DEPEND_TAGS.each do |tag|
                    describe "<#{tag}>" do
                        it "raises if the tag has neither a name nor a package attribute" do
                            assert_raises(InvalidPackageManifest) do
                                PackageManifest.parse(pkg, "<package><#{tag}>\n</#{tag}></package>", loader_class: Autoproj::PackageManifest::RosLoader)
                            end
                        end
                        it "parses the dependency name" do
                            dependency = parse_dependency("<package><#{tag}>test</#{tag}></package>")
                            assert_equal 'test', dependency.name
                        end
                        it "is not optional" do
                            dependency = parse_dependency("<package><#{tag}>test</#{tag}></package>")
                            refute dependency.optional
                        end
                    end
                end
                Autoproj::PackageManifest::RosLoader::SUPPORTED_MODES.each do |mode|
                    tag = "#{mode}_depend"
                    describe "<#{tag}>" do
                        it "raises if the tag has neither a name nor a package attribute" do
                            assert_raises(InvalidPackageManifest) do
                                PackageManifest.parse(pkg, "<package><#{tag}>\n</#{tag}></package>", loader_class: Autoproj::PackageManifest::RosLoader)
                            end
                        end
                        it "parses the dependency name and mode" do
                            dependency = parse_dependency("<package><#{tag}>test</#{tag}></package>")
                            assert_equal 'test', dependency.name
                            assert_equal ['test'], dependency.modes
                        end
                        it "is not optional" do
                            dependency = parse_dependency("<package><#{tag}>test</#{tag}></package>")
                            refute dependency.optional
                        end
                    end
                end
            end

            describe "authors" do
                it "parses the author tag" do
                    manifest = subject_parse('<package><author email="name@domain">Firstname Lastname</author><author email="author2@domain">Author2</author></package>')
                    assert_equal [PackageManifest::ContactInfo.new('Firstname Lastname', 'name@domain'),
                                  PackageManifest::ContactInfo.new('Author2', 'author2@domain')], manifest.authors
                end
            end

            describe "maintainers" do
                it "parses the maintainer tag" do
                    manifest = subject_parse('<package><maintainer email="name@domain">Firstname Lastname</maintainer><maintainer email="author2@domain">Author2</maintainer></package>')
                    assert_equal [PackageManifest::ContactInfo.new('Firstname Lastname', 'name@domain'),
                                  PackageManifest::ContactInfo.new('Author2', 'author2@domain')], manifest.maintainers
                end
            end
        end

        #def test_complete_manifest
        #    deps = [['dep1', false], ['dep2', false]]
        #    opt_deps = [['opt_dep1', true], ['opt_dep2', true]]
        #    osdeps = [['osdep1', false]]

        #    assert_equal((deps + opt_deps + osdeps).to_set, manifest.each_dependency.to_set)

        #    authors = [
        #        ["Author1", "author1@email"],
        #        ["Author2", "author2@email"],
        #        ["Author3", nil]]
        #    assert_equal(authors.to_set, manifest.each_author.to_set)

        #    assert_equal('the_url', manifest.url)
        #    assert_equal('BSD', manifest.license)
        #end

        #def test_empty_manifest
        #    data = File.join(DATA_DIR, 'empty_manifest.xml')
        #    manifest = Autoproj::PackageManifest.load(pkg, data)

        #    assert_equal [], manifest.tags
        #    assert_match /no documentation available/, manifest.documentation
        #    assert_match /no documentation available/, manifest.short_documentation

        #    assert(manifest.each_os_dependency.to_a.empty?)
        #    assert(manifest.each_package_dependency.to_a.empty?)
        #    assert(manifest.each_dependency.to_a.empty?)
        #    assert(manifest.each_author.to_a.empty?)

        #    assert_equal(nil, manifest.url)
        #    assert_equal(nil, manifest.license)
        #end

        #def test_failure_on_wrong_document
        #    data = File.join(DATA_DIR, 'invalid_manifest.xml')
        #    assert_raises(Autobuild::PackageException) { Autoproj::PackageManifest.load(pkg, data) }
        #end
    end
end

class TC_PackageManifest < Minitest::Test

    DATA_DIR = File.expand_path('data', File.dirname(__FILE__))

end

