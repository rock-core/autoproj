require "autoproj/test"
require "autoproj/ops/build"
require "json"
require "timecop"

module Autoproj
    module Ops
        describe Build do
            before do
                @ws = ws_create
                @packages = (0...3).map do |i|
                    pkg = Autobuild::Package.new("pkg#{i}")
                    ws_setup_package pkg
                end

                @reporting = flexmock(Ops::PhaseReporting).new_instances
                @build = Build.new(@ws.manifest, report_path: @ws.build_report_path)

                Timecop.freeze

                flexmock(@packages[0].autobuild,
                         install_invoked?: true, installed?: true)
                flexmock(@packages[1].autobuild,
                         install_invoked?: true, installed?: false)
                flexmock(@packages[2].autobuild,
                         install_invoked?: false, installed?: false)
            end

            after do
                Timecop.return
            end

            it "writes a report incrementally" do
                %w[pkg0 pkg1 pkg2].each do |pkg_name|
                    @reporting.should_receive(:report_incremental)
                              .once.with(->(p) { p.name == pkg_name }).pass_thru do
                        assert current_report["build_report"]["packages"][pkg_name]
                    end
                end

                @build.build_packages(%w[pkg0 pkg1 pkg2])
            end

            it "exports the status the processed packages" do
                @build.build_packages(%w[pkg0 pkg1 pkg2])
                json = current_report
                assert_equal(
                    {
                        "build_report" => {
                            "timestamp" => Time.now.to_s,
                            "packages" => {
                                "pkg0" => { "invoked" => true, "success" => true },
                                "pkg1" => { "invoked" => true, "success" => false },
                                "pkg2" => { "invoked" => false, "success" => false }
                            }
                        }
                    }, json
                )
            end

            def current_report
                data = File.read(@ws.build_report_path)
                JSON.parse(data)
            end
        end
    end
end
