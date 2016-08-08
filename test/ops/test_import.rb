require 'autoproj/test'

module Autoproj
    module Ops
        describe Import do
            before do
                ws_create
                ws_define_package :cmake, '0'
                ws_define_package :cmake, '1'
                ws_define_package :cmake, '11'
                ws_define_package :cmake, '12'
                ws.manifest.exclude_package '0', 'reason0'
            end

            subject { Import.new(ws) }
            let(:revdeps) { Hash['0' => %w{1}, '1' => %w{11 12}] }

            describe "#mark_exclusion_along_revdeps" do
                it "marks all packages that depend on an excluded package as excluded" do
                    subject.mark_exclusion_along_revdeps('0', revdeps)
                    assert ws.manifest.excluded?('1')
                    assert ws.manifest.excluded?('11')
                    assert ws.manifest.excluded?('12')
                end
                it "stores the dependency chain in the exclusion reason for links of more than one hop" do
                    subject.mark_exclusion_along_revdeps('0', revdeps)
                    assert_match(/11>1>0/, ws.manifest.exclusion_reason('11'))
                    assert_match(/12>1>0/, ws.manifest.exclusion_reason('12'))
                end
                it "stores the original package's reason in the exclusion reason" do
                    subject.mark_exclusion_along_revdeps('0', revdeps)
                    assert_match(/reason0/, ws.manifest.exclusion_reason('1'))
                    assert_match(/reason0/, ws.manifest.exclusion_reason('11'))
                    assert_match(/reason0/, ws.manifest.exclusion_reason('12'))
                end
                it "ignores packages that are already excluded" do
                    ws.manifest.exclude_package '11', 'reason11'
                    flexmock(ws.manifest).should_receive(:exclude_package).with(->(name) { name != '11' }, any).twice.pass_thru
                    subject.mark_exclusion_along_revdeps('0', revdeps)
                end
            end
        end
    end
end

