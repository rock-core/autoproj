require "autoproj/test"

module Autoproj
    describe SourcePackageQuery do
        before do
            ws_create
        end

        describe "#match" do
            before do
                @pkg = ws_define_package "cmake", "test/package"
            end

            it "returns nil if no method matches" do
                q = SourcePackageQuery.new(%w[autobuild name], "not_matching", false)
                assert_nil q.match(@pkg)
            end

            it "returns EXACT if the field matches the value" do
                q = SourcePackageQuery.new(%w[autobuild name], "test/package", false)
                assert_equal SourcePackageQuery::EXACT, q.match(@pkg)
            end

            it "returns PARTIAL on a partial match if partial matching is enabled" do
                q = SourcePackageQuery.new(%w[autobuild name], "package", true)
                assert_equal SourcePackageQuery::PARTIAL, q.match(@pkg)
            end

            it "returns nil on a partial match if partial matching is disabled" do
                q = SourcePackageQuery.new(%w[autobuild name], "package", false)
                assert_nil q.match(@pkg)
            end

            it "returns DIR_PREFIX_STRONG if the value is slash-separated and the last value is exact" do
                q = SourcePackageQuery.new(%w[autobuild name], "te/package", true)
                assert_equal SourcePackageQuery::DIR_PREFIX_STRONG, q.match(@pkg)
            end
            it "disables DIR_PREFIX_STRONG matching if partial match is disabled" do
                q = SourcePackageQuery.new(%w[autobuild name], "te/package", false)
                assert_nil q.match(@pkg)
            end
            it "returns DIR_PREFIX_WEAK if the value is slash-separated and the last value is not exact" do
                q = SourcePackageQuery.new(%w[autobuild name], "te/p", true)
                assert_equal SourcePackageQuery::DIR_PREFIX_WEAK, q.match(@pkg)
            end
            it "disables DIR_PREFIX_WEAK matching if partial match is disabled" do
                q = SourcePackageQuery.new(%w[autobuild name], "te/p", false)
                assert_nil q.match(@pkg)
            end
        end

        describe ".parse" do
            it "partially matches on name and srcdir for pure values" do
                q = SourcePackageQuery.parse("test")
                assert_kind_of SourcePackageQuery::Or, q
                sub = q.each_subquery.to_a
                assert_equal 2, sub.size

                q0 = sub[0]
                assert_equal %w[autobuild name], q0.fields
                assert_equal "test", q0.value
                assert q0.partial?
                q1 = sub[1]
                assert_equal %w[autobuild srcdir], q1.fields
                assert_equal "test", q1.value
                assert q1.partial?
            end
        end
    end
end
