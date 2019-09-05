require 'autoproj/test'
require 'autoproj/ops/build'
require 'json'
require 'timecop'

module Autoproj
    module Ops
        describe Build do
            before do
                @ws = ws_create
                @pkg1 = ws_define_package :cmake, 'pkg1'
                @pkg2 = ws_define_package :cmake, 'pkg2'
                @pkg3 = ws_define_package :cmake, 'pkg3'

                @build = Build.new(ws.manifest, report_path: @ws.build_report_path)

                @pkg1object = ws.manifest.find_autobuild_package('pkg1')
                @pkg2object = ws.manifest.find_autobuild_package('pkg2')
                @pkg3object = ws.manifest.find_autobuild_package('pkg3')

                Timecop.freeze

                flexmock(@pkg1object)
                @pkg1object.should_receive(install_invoked?: true)
                @pkg1object.should_receive(installed?: true)

                flexmock(@pkg2object)
                @pkg2object.should_receive(install_invoked?: true)
                @pkg2object.should_receive(installed?: false)

                flexmock(@pkg3object)
                @pkg3object.should_receive(install_invoked?: false)
                @pkg3object.should_receive(installed?: false)
            end

            after do
                Timecop.return
            end

            it "works even if given no packages to work on" do
                @build.create_report([])
                json = read_report
                assert_equal({
                    'build_report' => {
                        'timestamp' => Time.now.to_s,
                        'packages' => {}
                    }
                }, json)
            end

            it "works with just one successful package" do
                @build.create_report(['pkg1'])
                json = read_report
                assert_equal({
                    'build_report' => {
                        'timestamp' => Time.now.to_s,
                        'packages' => {
                            'pkg1' => { 'invoked' => true, 'success' => true },
                        }
                    }
                }, json)
            end

            it "works with just one failed package" do
                @build.create_report(['pkg2'])
                json = read_report
                assert_equal({
                    'build_report' => {
                        'timestamp' => Time.now.to_s,
                        'packages' => {
                            'pkg2' => { 'invoked' => true, 'success' => false },
                        }
                    }
                }, json)
            end


            it "exports the status of several given packages" do
                @build.create_report(['pkg1','pkg2', 'pkg3'])
                json = read_report
                assert_equal({
                    'build_report' => {
                        'timestamp' => Time.now.to_s,
                        'packages' => {
                            'pkg1' => { 'invoked' => true, 'success' => true },
                            'pkg2' => { 'invoked' => true, 'success' => false },
                            'pkg3' => { 'invoked' => false, 'success' => false }
                        }
                    }
                }, json)
            end

            def read_report
                data = File.read(@ws.build_report_path)
                JSON.parse(data)
            end
        end
    end
end

