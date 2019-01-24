require 'autoproj/test'
require 'autoproj/ops/build'
require 'json'

module Autoproj
    module Ops
        describe Build do
            before do
                @ws = ws_create
                @pkg1_test = ws_define_package :cmake, 'pkg1'
                @pkg2_test = ws_define_package :cmake, 'pkg2'
                @build = Build.new(ws.manifest, report_dir: @ws.log_dir)
                flexmock(Time).should_receive('now').and_return(Time.mktime(1970,1,1))
            end

            it "works even if given no packages to work on" do
                @build.build_report([])
                json = read_report
                assert_equal Hash['build_report' => {'timestamp' => Time.mktime(1970,1,1).to_s, 'packages' => []}], json
            end

            it "works with just one package" do
                @build.build_report(['pkg1'])
                json = read_report
                assert_equal Hash['build_report' => {'timestamp' => Time.mktime(1970,1,1).to_s,'packages' => [expected_package('pkg1')]}], json
            end

            it "exports the status of the given packages" do
                @build.build_report(['pkg1','pkg2'])
                json = read_report
                assert_equal Hash['build_report' => {'timestamp' => Time.mktime(1970,1,1).to_s,'packages' => [expected_package('pkg1'),expected_package('pkg2')]}], json
            end

            def read_report
                data = File.read(File.join(@ws.log_dir, "build_report.json"))
                JSON.load(data)
            end

            def expected_package(pkg_name)
                Hash[
                 'name' => pkg_name,
                 'import_invoked' => 'false',
                 'prepare_invoked' => 'false',
                 'build_invoked' => 'false',
                 'failed' => "",
                 'imported'=>'false',
                 'prepared'=>'false',
                 'built'=>'false']
            end
        end
    end
end

