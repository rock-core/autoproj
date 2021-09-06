require "autoproj/test"

module Autoproj
    describe QueryBase do
        before do
            match_class = Class.new do
                attr_reader :fields, :value
                def partial?
                    @partial
                end
                def initialize(fields, value, partial)
                    @fields, @value, @partial = fields, value, partial
                end
            end

            @query_class = Class.new(QueryBase) do
                singleton_class.class_eval do
                    define_method :parse do |str, **options|
                        match_class.new(*super(str, **Hash[allowed_fields: ["test.field"]].merge(options)))
                    end
                end
            end
        end

        describe ".all" do
            it "returns an object that matches anything" do
                assert QueryBase.all.match(flexmock)
            end
        end

        describe ".parse" do
            it "parses FIELD=VALUE as an exact match" do
                query = @query_class.parse("test.field=20")
                assert_equal %w[test field], query.fields
                assert_equal "20", query.value
                refute query.partial?
            end
            it "parses FIELD~VALUE as a partial match" do
                query = @query_class.parse("test.field~20")
                assert_equal %w[test field], query.fields
                assert_equal "20", query.value
                assert query.partial?
            end
            it "raises if the string contains neither = nor ~" do
                e = assert_raises(ArgumentError) { @query_class.parse("20") }
                assert_equal "invalid query string '20', expected FIELD and VALUE separated by either = or ~", e.message
            end
            it "raises if the FIELD is not in the list of allowed fields" do
                e = assert_raises(ArgumentError) { @query_class.parse("test.bla=20") }
                assert_equal "'test.bla' is not a known query key", e.message
            end
            it "maps FIELD using the default fields first" do
                query = @query_class.parse("unknown~20", allowed_fields: ["test.field"], default_fields: { "unknown" => "test.field" })
                assert_equal %w[test field], query.fields
                assert_equal "20", query.value
                assert query.partial?
            end
        end

        describe ".parse_query" do
            it "returns a single query as-is" do
                query = @query_class.parse_query("test.field=20")
                assert_equal %w[test field], query.fields
                assert_equal "20", query.value
                refute query.partial?
            end

            it "combines multiple queries using the And" do
                query = @query_class.parse_query("test.field=20:test.field~0")
                assert_kind_of QueryBase::And, query
                sub = query.each_subquery.to_a
                assert_equal 2, sub.size

                q0 = sub[0]
                assert_equal %w[test field], q0.fields
                assert_equal "20", q0.value
                refute q0.partial?

                q1 = sub[1]
                assert_equal %w[test field], q1.fields
                assert_equal "0", q1.value
                assert q1.partial?
            end
        end
    end
end
