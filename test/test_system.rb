# frozen_string_literal: true

require "autoproj/test"
require "autoproj/cli/main"
require "autoproj/cli/update"

module Autoproj
    describe "system tests" do
        attr_reader :manifest_path
        attr_reader :pkg_set_path
        attr_reader :pkg_set
        attr_reader :pkg

        before do
            ws_create

            @pkg_set_path = File.join(ws.config_dir, "pkg_set0")
            @pkg_set = ws_create_local_package_set(
                "pkg_set0",
                pkg_set_path,
                source_data: source_data
            )

            ws_create_package_set_file(pkg_set, "test.autobuild", autobuild_contents)
            @manifest_path = File.join(ws.config_dir, "manifest")
            File.write(manifest_path, manifest_contents)
            FileUtils.mkdir_p(File.join(ws.root_dir, "pkg0"))
        end

        def autobuild_contents
            <<~EOFAUTOBUILD
                import_package "pkg0"
            EOFAUTOBUILD
        end

        def source_data
            {
                "version_control" =>
                    [
                        "pkg0" => nil,
                        "type" => "local",
                        "url" => File.join(ws.root_dir, "pkg0")
                    ]
            }
        end

        def manifest_contents
            <<~EOFMANIFEST
                package_sets:
                    - pkg_set0

                layout:
                    - pkg0
            EOFMANIFEST
        end

        describe "ignored packages" do
            before do
                File.open(File.join(pkg_set_path, "ignored.autobuild"), "w") do |f|
                    content = <<~EOFCONTENT
                        import_package "pkg1" do |pkg|
                            package("pkg0").depends_on "pkg1"
                        end

                        Autoproj.workspace
                                .current_package_set
                                .add_version_control_entry(
                                    "pkg1",
                                    { type: "git", url: "https://remote" }
                                )

                        Autoproj.workspace.manifest.ignore_package("pkg1")
                    EOFCONTENT

                    f.write(content)
                end
            end

            it "updates a workspace with ignored packages" do
                in_ws do
                    CLI::Main.start(%w[update --no-autoproj])
                end
            end

            it "builds a workspace with ignored packages" do
                in_ws do
                    CLI::Main.start(%w[build])
                end
            end
        end
    end
end
