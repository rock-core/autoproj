module Autoproj
    # Access to the information contained in a package's package.xml file
    #
    # Use PackageManifest.load to create
    class RosPackageManifest < PackageManifest
        attr_accessor :name

        # @api private
        #
        # REXML stream parser object used to load the XML contents into a
        # {PackageManifest} object
        class Loader < PackageManifest::Loader
            MANIFEST_CLASS = RosPackageManifest
            SUPPORTED_MODES = %w[test doc].freeze
            DEPEND_TAGS = %w[depend build_depend build_export_depend
                             buildtool_depend buildtool_export_depend
                             exec_depend test_depend run_depend doc_depend].to_set.freeze

            def toplevel_tag_start(name, attributes)
                if DEPEND_TAGS.include?(name)
                    @tag_text = ""
                elsif TEXT_FIELDS.include?(name)
                    @tag_text = ""
                elsif AUTHOR_FIELDS.include?(name)
                    @author_email = attributes["email"]
                    @tag_text = ""
                elsif name == "name"
                    @tag_text = ""
                else
                    @tag_text = nil
                end
            end

            def toplevel_tag_end(name)
                if DEPEND_TAGS.include?(name)
                    if @tag_text.strip.empty?
                        raise InvalidPackageManifest, "found '#{name}' tag in #{path} "\
                                                      "without content"
                    end

                    mode = []
                    if (m = /^(\w+)_depend$/.match(name))
                        mode = SUPPORTED_MODES & [m[1]]
                    end

                    manifest.add_dependency(@tag_text, modes: mode)
                elsif AUTHOR_FIELDS.include?(name)
                    author_name = @tag_text.strip
                    email = @author_email ? @author_email.strip : nil
                    email = nil if email&.empty?
                    contact = PackageManifest::ContactInfo.new(author_name, email)
                    manifest.send("#{name}s").concat([contact])
                elsif TEXT_FIELDS.include?(name)
                    field = @tag_text.strip
                    manifest.send("#{name}=", field) unless field.empty?
                elsif name == "name"
                    manifest.name = @tag_text.strip
                end
                @tag_text = nil
            end
        end
    end
end
