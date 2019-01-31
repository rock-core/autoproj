require 'autoproj/test'
require 'autoproj/ops/build'
require 'json'

module Autoproj
    module Ops
        describe Build do
            before do
                @ws = ws_create
                @pkg1 = ws_define_package :cmake, 'pkg1'
                @pkg2 = ws_define_package :cmake, 'pkg2'
                @pkg3 = ws_define_package :cmake, 'pkg3'

                @build = Build.new(ws.manifest, report_dir: @ws.log_dir)

                @pkg1object = ws.manifest.find_autobuild_package('pkg1')
                @pkg2object = ws.manifest.find_autobuild_package('pkg2')
                @pkg3object = ws.manifest.find_autobuild_package('pkg3')

                set_success_flags(@pkg1object)
                set_failed_flags(@pkg2object)
                set_failed_flags(@pkg3object)

                flexmock(Time).should_receive('now').and_return(Time.mktime(1970,1,1))

                flexmock(@pkg1object)
                .should_receive('prepare_invoked?')
                .and_return(true)

                flexmock(@pkg1object)
                .should_receive('import_invoked?')
                .and_return(true)

                flexmock(@pkg1object)
                .should_receive('build_invoked?')
                .and_return(true)

            end

            it "works even if given no packages to work on" do
                @build.build_report([])
                json = read_report
                assert_equal Hash['build_report' => {
                                    'timestamp' => Time.mktime(1970,1,1).to_s, 
                                    'packages' => []
                                }], json
            end

            it "works with just one successful package" do
                @build.build_report(['pkg1'])
                json = read_report
                assert_equal Hash['build_report' => {
                                    'timestamp' => Time.mktime(1970,1,1).to_s,
                                    'packages' => [expected_successful_package('pkg1')]
                                }], json
            end

            it "works with just one failed package" do
                @build.build_report(['pkg2'])
                json = read_report
                assert_equal Hash['build_report' => {
                                    'timestamp' => Time.mktime(1970,1,1).to_s,
                                    'packages' => [expected_failed_package('pkg2')]
                                }], json
            end


            it "exports the status of several given packages" do
                @build.build_report(['pkg1','pkg2', 'pkg3'])
                json = read_report
                assert_equal Hash['build_report' => {
                    'timestamp' => Time.mktime(1970,1,1).to_s,
                    'packages' => [ expected_successful_package('pkg1'),
                                    expected_failed_package('pkg2'),
                                    expected_failed_package('pkg3')
                                  ]
                    }], json
            end

            def read_report
                data = File.read(File.join(@ws.log_dir, "build_report.json"))
                JSON.load(data)
            end

            def set_success_flags(package)
                package.instance_variable_set(:@prepared, true) 
                package.instance_variable_set(:@imported, true) 
                package.instance_variable_set(:@built, true) 
                package.instance_variable_set(:@failed, nil) 
            end

            def set_failed_flags(package)
                package.instance_variable_set(:@prepared, false) 
                package.instance_variable_set(:@imported, false) 
                package.instance_variable_set(:@built, false) 
                package.instance_variable_set(:@failed, true) 
            end

            def expected_successful_package(pkg_name)
                Hash[
                 'name' => pkg_name,
                 'import_invoked' => true,
                 'prepare_invoked' => true,
                 'build_invoked' => true,
                 'failed' => nil,
                 'imported'=> true,
                 'prepared'=> true,
                 'built'=> true]
            end

            def expected_failed_package(pkg_name)
                Hash[
                 'name' => pkg_name,
                 'import_invoked' => false,
                 'prepare_invoked' => false,
                 'build_invoked' => false,
                 'failed' => true,
                 'imported'=> false,
                 'prepared'=> false,
                 'built'=> false]
            end
        end
    end
end

