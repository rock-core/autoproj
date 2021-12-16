require "autoproj/test"

module Autoproj
    describe PackageManifest do
        attr_reader :pkg

        before do
            @pkg = flexmock(name: "test")
        end

        def subject_parse(text)
            Autoproj::PackageManifest.parse(pkg, text, loader_class: Autoproj::RosPackageManifest::Loader)
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
                loader_class = Autoproj::RosPackageManifest::Loader
                manifest = PackageManifest.parse(pkg, xml, loader_class: loader_class)
                assert_equal 1, manifest.dependencies.size
                manifest.dependencies.first
            end

            Autoproj::RosPackageManifest::Loader::DEPEND_TAGS.each do |tag|
                describe "<#{tag}>" do
                    it "raises if the tag has neither a name nor a package attribute" do
                        assert_raises(InvalidPackageManifest) do
                            PackageManifest.parse(pkg, "<package><#{tag}>\n</#{tag}></package>", loader_class: Autoproj::RosPackageManifest::Loader)
                        end
                    end
                    it "parses the dependency name" do
                        dependency = parse_dependency("<package><#{tag}>test</#{tag}></package>")
                        assert_equal "test", dependency.name
                    end
                    it "is not optional" do
                        dependency = parse_dependency("<package><#{tag}>test</#{tag}></package>")
                        refute dependency.optional
                    end
                end
            end
            Autoproj::RosPackageManifest::Loader::SUPPORTED_MODES.each do |mode|
                tag = "#{mode}_depend"
                describe "<#{tag}>" do
                    it "raises if the tag has neither a name nor a package attribute" do
                        assert_raises(InvalidPackageManifest) do
                            PackageManifest.parse(pkg, "<package><#{tag}>\n</#{tag}></package>", loader_class: Autoproj::RosPackageManifest::Loader)
                        end
                    end
                    it "parses the dependency name and mode" do
                        dependency = parse_dependency("<package><#{tag}>test</#{tag}></package>")
                        assert_equal "test", dependency.name
                        assert_equal [mode], dependency.modes
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
                assert_equal [PackageManifest::ContactInfo.new("Firstname Lastname", "name@domain"),
                              PackageManifest::ContactInfo.new("Author2", "author2@domain")], manifest.authors
            end
        end

        describe "maintainers" do
            it "parses the maintainer tag" do
                manifest = subject_parse('<package><maintainer email="name@domain">Firstname Lastname</maintainer><maintainer email="author2@domain">Author2</maintainer></package>')
                assert_equal [PackageManifest::ContactInfo.new("Firstname Lastname", "name@domain"),
                              PackageManifest::ContactInfo.new("Author2", "author2@domain")], manifest.maintainers
            end
        end
    end
end
