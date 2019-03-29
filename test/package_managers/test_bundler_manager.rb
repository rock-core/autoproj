require 'autoproj/test'

module Autoproj
    module PackageManagers
        describe BundlerManager do
            describe ".run_bundler" do
                it "defaults to the workspace's shim if program['bundler'] is not initialized" do
                    Autobuild.programs['bundle'] = nil
                    ws = flexmock(dot_autoproj_dir: '/some/path')
                    ws.should_receive(:run)
                      .with(any, any, '/some/path/bin/bundle', 'some', 'program', Hash, Proc)
                      .once
                    BundlerManager.run_bundler(ws, 'some', 'program',
                                               gem_home: '/gem/home',
                                               gemfile: '/gem/path/Gemfile')
                end
            end
        end
    end
end
