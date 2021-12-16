# frozen_string_literal: true

require "autoproj/test"

module Autoproj
    describe PackageManifest do
        attr_reader :pkg

        before do
            @pkg = flexmock(name: "test")
        end

        def loader_class
            Autoproj::RosPackageManifest::Loader
        end

        def subject_parse(text)
            Autoproj::PackageManifest.parse(pkg, text, loader_class: loader_class)
        end

        describe "description" do
            it "loads the content of the description block" do
                subject = <<~EOFSUBJECT
                    <package>
                        <name>ros_pkg</name>
                        <description>long\ndocumentation\nblock</description>
                    </package>
                EOFSUBJECT

                manifest = subject_parse(subject)
                assert_equal "long\ndocumentation\nblock", manifest.documentation
            end
            it "allows html tags in a long description block" do
                subject = <<~EOFSUBJECT
                    <package>
                        <name>ros_pkg</name>
                        <description>long <tt>test</tt> documentation block</description>
                    </package>"
                EOFSUBJECT

                manifest = subject_parse(subject)
                assert_equal "long test documentation block", manifest.documentation
            end
            it "reports if there is no documentation" do
                manifest = subject_parse("<package><name>ros_pkg</name></package>")
                refute manifest.has_documentation?
            end
            it "reports if there is no documentation" do
                subject = <<~EOFSUBJECT
                    <package>
                        <name>ros_pkg</name>
                        <description/>
                    </package>
                EOFSUBJECT

                manifest = subject_parse(subject)
                refute manifest.has_documentation?
            end
            it "interprets an empty documentation text as no documentation" do
                subject = <<~EOFSUBJECT
                    <package>
                        <name>ros_pkg</name>
                        <description>  \n  </description>
                    </package>"
                EOFSUBJECT

                manifest = subject_parse(subject)
                refute manifest.has_documentation?
            end
            it "returns a default string if there is no documentation at all" do
                manifest = subject_parse("<package><name>ros_pkg</name></package>")
                assert_equal "no documentation available for package 'test'"\
                             " in its manifest.xml file",
                             manifest.documentation
            end
            it "returns a default string if there is no brief documentation" do
                subject = <<~EOFSUBJECT
                    <package>
                        <name>ros_pkg</name>
                        <documentation>long</documentation>
                    </package>
                EOFSUBJECT

                manifest = subject_parse(subject)
                assert_equal "no documentation available for package 'test'"\
                             " in its manifest.xml file",
                             manifest.short_documentation
            end
            it "reports if there is no brief documentation" do
                subject = <<~EOFSUBJECT
                    <package>
                        <name>ros_pkg</name>
                        <documentation>long</documentation>
                    </package>
                EOFSUBJECT

                manifest = subject_parse(subject)
                refute manifest.has_short_documentation?
            end
        end

        describe "dependencies" do
            def parse_dependency(xml)
                manifest = PackageManifest.parse(pkg, xml, loader_class: loader_class)
                assert_equal 1, manifest.dependencies.size
                manifest.dependencies.first
            end

            Autoproj::RosPackageManifest::Loader::DEPEND_TAGS.each do |tag|
                describe "<#{tag}>" do
                    it "raises if the tag has neither a name nor a package attribute" do
                        subject = "<package><name>ros_pkg</name>"\
                                  "<#{tag}>\n</#{tag}></package>"

                        assert_raises(InvalidPackageManifest) do
                            PackageManifest.parse(
                                pkg, subject, loader_class: loader_class
                            )
                        end
                    end
                    it "parses the dependency name" do
                        dependency = parse_dependency(
                            "<package><name>ros_pkg</name><#{tag}>test</#{tag}></package>"
                        )

                        assert_equal "test", dependency.name
                    end
                    it "is not optional" do
                        dependency = parse_dependency(
                            "<package><name>ros_pkg</name><#{tag}>test</#{tag}></package>"
                        )

                        refute dependency.optional
                    end
                end
            end
            Autoproj::RosPackageManifest::Loader::SUPPORTED_MODES.each do |mode|
                tag = "#{mode}_depend"
                describe "<#{tag}>" do
                    it "raises if the tag has neither a name nor a package attribute" do
                        subject = "<package><name>ros_pkg</name>"\
                                  "<#{tag}>\n</#{tag}></package>"

                        assert_raises(InvalidPackageManifest) do
                            PackageManifest.parse(
                                pkg, subject, loader_class: loader_class
                            )
                        end
                    end
                    it "parses the dependency name and mode" do
                        dependency = parse_dependency(
                            "<package><name>ros_pkg</name><#{tag}>test</#{tag}></package>"
                        )

                        assert_equal "test", dependency.name
                        assert_equal [mode], dependency.modes
                    end
                    it "is not optional" do
                        dependency = parse_dependency(
                            "<package><name>ros_pkg</name><#{tag}>test</#{tag}></package>"
                        )

                        refute dependency.optional
                    end
                end
            end
        end

        describe "name" do
            it "parses ros package name" do
                manifest = subject_parse("<package><name>ros_pkg</name></package>")
                assert_equal "ros_pkg", manifest.name
            end
        end

        describe "export level tags" do
            it "parses tags after an export level tag" do
                subject = <<~EOFSUBJECT
                    <package>
                        <export></export>
                        <name>ros_pkg</name>
                    </package>
                EOFSUBJECT

                manifest = subject_parse(subject)
                assert_equal "ros_pkg", manifest.name
            end

            it "differentiates export level tags from top level tags" do
                subject = <<~EOFSUBJECT
                    <package>
                        <export>
                            <name>ros_pkg</name>
                        </export>
                    </package>
                EOFSUBJECT

                assert_raises(InvalidPackageManifest) { subject_parse(subject) }
            end

            it "differentiates non export level tags from top level tags" do
                subject = <<~EOFSUBJECT
                    <package>
                        <name>ros_pkg</name>
                        <not_export>
                            <build_type>ament_cmake</build_type>
                        </not_export>
                    </package>
                EOFSUBJECT

                manifest = subject_parse(subject)
                assert_equal "catkin", manifest.build_type
            end

            it "defaults build_type to catkin" do
                manifest = subject_parse(
                    "<package><name>ros_pkg</name><export></export></package>"
                )
                assert_equal "catkin", manifest.build_type
            end

            it "parses build_type tag" do
                subject = <<~EOFSUBJECT
                    <package>
                        <name>ros_pkg</name>
                        <export>
                            <build_type>ament_cmake</build_type>
                        </export>
                    </package>
                EOFSUBJECT

                manifest = subject_parse(subject)
                assert_equal "ament_cmake", manifest.build_type
            end
        end

        describe "authors" do
            it "parses the author tag" do
                subject = <<~EOFSUBJECT
                    <package>
                        <name>ros_pkg</name>
                        <author email="name@domain">Firstname Lastname</author>
                        <author email="author2@domain">Author2</author>
                    </package>
                EOFSUBJECT

                manifest = subject_parse(subject)
                contact1 = PackageManifest::ContactInfo.new(
                    "Firstname Lastname", "name@domain"
                )
                contact2 = PackageManifest::ContactInfo.new(
                    "Author2", "author2@domain"
                )
                assert_equal [contact1, contact2], manifest.authors
            end
        end

        describe "maintainers" do
            it "parses the maintainer tag" do
                subject = <<~EOFSUBJECT
                    <package>
                        <name>ros_pkg</name>
                        <maintainer email="name@domain">Firstname Lastname</maintainer>
                        <maintainer email="author2@domain">Author2</maintainer>
                    </package>
                EOFSUBJECT

                manifest = subject_parse(subject)
                contact1 = PackageManifest::ContactInfo.new(
                    "Firstname Lastname", "name@domain"
                )
                contact2 = PackageManifest::ContactInfo.new(
                    "Author2", "author2@domain"
                )
                assert_equal [contact1, contact2], manifest.maintainers
            end
        end
    end
end
