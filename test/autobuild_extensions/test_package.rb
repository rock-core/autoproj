# frozen_string_literal: true

require "autoproj/test"
require "autoproj/autobuild_extensions/package"
require "autobuild/package"

module Autobuild
    describe Package do
        describe "#depends_on" do
            it "does not add a dependency on an ignored package" do
                ws = ws_create
                foo = ws_define_package :cmake, "foo"
                bar = ws_define_package :cmake, "bar"

                ws.manifest.ignore_package(foo)
                bar.depends_on(foo)
                assert bar.autobuild.dependencies.empty?
            end
        end
    end
end
