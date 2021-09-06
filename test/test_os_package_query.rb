require "autoproj/test"

module Autoproj
    describe OSPackageQuery do
        before do
            ws_create
            ws_create_os_package_resolver
            ws_define_osdep_entries("pkg1" => { "os" => "test" })
            ws_define_osdep_entries("pkg2" => { "os" => "test" })
            ws_define_osdep_entries("another" => { "os_indep" => "something_else" })
        end

        describe "#match" do
            it "matches on name" do
                query = OSPackageQuery.parse("name~pkg", ws_os_package_resolver)
                assert query.match("pkg1")
                assert query.match("pkg2")
                refute query.match("another")
            end

            it "matches on actual packages" do
                query = OSPackageQuery.parse("real_package=test", ws_os_package_resolver)
                assert query.match("pkg1")
                assert query.match("pkg2")
                refute query.match("another")
            end

            it "matches on package manager" do
                query = OSPackageQuery.parse("package_manager=os_indep", ws_os_package_resolver)
                refute query.match("pkg1")
                refute query.match("pkg2")
                assert query.match("another")
            end
        end
    end
end
