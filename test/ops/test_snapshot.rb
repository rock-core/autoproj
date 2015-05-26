require 'autoproj/test'

module Autoproj
    module Ops
        describe Snapshot do
            attr_reader :manifest
            before do
                @manifest = create_bootstrap
            end

            describe ".update_log_available?" do
                it "returns false if the main configuration is not managed by git" do
                    assert !Snapshot.update_log_available?(manifest)
                end
                it "returns true if the main configuration is managed by git even if it is not declared" do
                    system("git", "init", chdir: Autoproj.config_dir, STDOUT => :close)
                    assert Snapshot.update_log_available?(manifest)
                end
                it "returns true if the main configuration is managed by git and it is declared" do
                    manifest.main_package_set.vcs = VCSDefinition.from_raw('type' => 'git', 'url' => Autoproj.config_dir)
                    assert Snapshot.update_log_available?(manifest)
                end
            end
        end
    end
end
