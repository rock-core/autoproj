require 'autoproj/test'

module Autoproj
    module Ops
        describe Snapshot do
            before do
                @ws = create_bootstrap
                ws.load_manifest
                ws.manifest.vcs =
                    VCSDefinition.from_raw('type' => 'local', 'url' => ws.config_dir)
            end

            describe ".update_log_available?" do
                it "returns false if the main configuration is not managed by git" do
                    assert !Snapshot.update_log_available?(ws.manifest)
                end
                it "returns true if the main configuration is managed by git even if it is not declared" do
                    system("git", "init", chdir: ws.config_dir, STDOUT => :close)
                    assert Snapshot.update_log_available?(ws.manifest)
                end
                it "returns true if the main configuration is managed by git and it is declared" do
                    ws.manifest.vcs =
                        VCSDefinition.from_raw('type' => 'git', 'url' => ws.config_dir)
                    assert Snapshot.update_log_available?(ws.manifest)
                end
            end
        end
    end
end
