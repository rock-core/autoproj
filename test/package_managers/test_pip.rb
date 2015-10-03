require 'autoproj/test'

module Autoproj
    module PackageManagers
        describe PipManager do
            attr_reader :pip_manager

            def setup
                OSPackageResolver.operating_system = [['test', 'debian', 'default'], ['v1.0', 'v1', 'default']]

                ws = flexmock(prefix_dir: '/prefix', env: Hash.new)
                @pip_manager = PipManager.new(ws)
                Autobuild.programs['pip'] = 'mypip'
                super
            end

            def teardown
                super
                Autobuild.programs['pip'] = nil
            end

            def test_install_packages
                subprocess = flexmock(Autobuild::Subprocess)

                packages = ['pkg0', 'pkg1', 'pkg2']
                subprocess.should_receive(:run).
                    with(any, any, 'mypip', 'install', '--user', 'pkg0', 'pkg1','pkg2').once
                pip_manager.install(packages)
            end

            def test_install_packaes_disabled_and_not_silent
                subprocess = flexmock(Autobuild::Subprocess)

                pip_manager.enabled = false
                pip_manager.silent = false
                subprocess.should_receive(:run).never
                flexmock(STDIN).should_receive(:readline).once.and_return
                pip_manager.install([['pkg0']])
            end
        end
    end
end

