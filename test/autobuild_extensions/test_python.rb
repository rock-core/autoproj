# frozen_string_literal: true

require "autoproj/test"

module Autoproj
    describe "#update_environment" do
        before do
            @ws = ws_create
            @pkg = ws_define_package :python, "pkg"
            FileUtils.touch(File.join(@pkg.autobuild.srcdir, "setup.py"))
        end
        it "activates python before fetching python's user site path" do
            flexmock(@pkg.autobuild).should_receive(:activate_python).once.ordered
            flexmock(@pkg.autobuild).should_receive(:python_path).once.ordered
            @pkg.autobuild.update_environment
        end
    end
end
