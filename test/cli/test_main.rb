require 'autoproj/test'
require 'autoproj/cli/main'
require 'autoproj/cli/versions'

module Autoproj
    module CLI
        describe Main do
            attr_reader :workspace_dir
            before do
                @workspace_dir = create_bootstrap.root_dir
            end

            describe "#versions" do
                before do
                    flexmock(Versions).new_instances.should_receive(:initialize_and_load)
                end

                def mock_finalize_setup(packages, config_selected)
                    flexmock(Versions).new_instances.should_receive(:finalize_setup).
                        and_return([packages, flexmock, config_selected])
                end

                def mock_should_snapshot_package_sets
                    flexmock(Ops::Snapshot).new_instances.
                        should_receive(:snapshot_package_sets).
                        and_return([])
                end

                def mock_should_snapshot_packages(packages)
                    flexmock(Ops::Snapshot).new_instances.
                        should_receive(:snapshot_packages).
                        with(['pkg'], nil, only_local: false).
                        and_return([])
                end

                def run_command(*args)
                    capture_subprocess_io do
                        Dir.chdir(workspace_dir) do
                            Main.start([*args, '--debug'], debug: true)
                        end
                    end
                end

                it "versions the package sets and the packages if no arguments are given" do
                    mock_finalize_setup(['pkg'], false)
                    mock_should_snapshot_package_sets.once
                    mock_should_snapshot_packages(['pkg']).once
                    run_command 'versions'
                end
                it "does not version the packages if only --config is given" do
                    mock_finalize_setup(['pkg'], false)
                    mock_should_snapshot_package_sets.once
                    mock_should_snapshot_packages(['pkg']).never
                    run_command 'versions', '--config'
                end
                it "does not version the package sets if only packages are given" do
                    mock_finalize_setup(['pkg'], false)
                    mock_should_snapshot_package_sets.never
                    mock_should_snapshot_packages(['pkg']).once
                    run_command 'versions', 'pkg'
                end
                it "versions both the package sets and the packages if both --config and packages are given" do
                    mock_finalize_setup(['pkg'], false)
                    mock_should_snapshot_package_sets.once
                    mock_should_snapshot_packages(['pkg']).once
                    run_command 'versions', '--config', 'pkg'
                end
                it "versions only the package sets if only the buildconf directory is given" do
                    mock_finalize_setup(['pkg'], true)
                    mock_should_snapshot_package_sets.once
                    mock_should_snapshot_packages(['pkg']).never
                    run_command 'versions', 'autoproj'
                end
                it "versions both the package sets and the packages if both the config directory and the packages are given" do
                    mock_finalize_setup(['pkg'], true)
                    mock_should_snapshot_package_sets.once
                    mock_should_snapshot_packages(['pkg']).once
                    run_command 'versions', 'autoproj', 'pkg'
                end
            end
        end
    end
end
