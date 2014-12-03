require 'autoproj/test'
require 'autoproj/ops/configuration'

describe Autoproj::Ops::Configuration do
    describe "#sort_package_sets_by_import_order" do
        attr_reader :ops

        before do
            @ops = Autoproj::Ops::Configuration.new(nil, nil)
        end

        it "should handle standalone package sets that are both explicit and dependencies of other package sets gracefully (issue#30)" do
            pkg_set0 = flexmock('set0', imports: [], explicit?: true)
            pkg_set1 = flexmock('set1', imports: [pkg_set0], explicit?: true)
            root_pkg_set = flexmock('root', imports: [pkg_set0, pkg_set1], explicit?: true)
            assert_equal [pkg_set0, pkg_set1, root_pkg_set],
                ops.sort_package_sets_by_import_order([pkg_set1, pkg_set0], root_pkg_set)
        end
    end
end
