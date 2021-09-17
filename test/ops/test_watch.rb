require "autoproj/test"
require "autoproj/ops/watch"

module Autoproj
    module Ops
        describe "the watch protocol" do
            before do
                ws_create
            end

            it "creates and releases the watch marker" do
                refute Ops.watch_running?(ws.root_dir)
                io = Ops.watch_create_marker(ws.root_dir)
                assert Ops.watch_running?(ws.root_dir)
                Ops.watch_cleanup_marker(io)
                refute Ops.watch_running?(ws.root_dir)
            end

            it "raises if two watches try to register themselves concurrently" do
                Ops.watch_create_marker(ws.root_dir)
                assert_raises(WatchAlreadyRunning) do
                    Ops.watch_create_marker(ws.root_dir)
                end
            end

            it "does behave even if a process died without removing the marker file" do
                io = Ops.watch_create_marker(ws.root_dir)
                io.close
                refute Ops.watch_running?(ws.root_dir)
            end

            it "does register the current process even if there is a leftover marker" do
                io = Ops.watch_create_marker(ws.root_dir)
                io.close
                Ops.watch_create_marker(ws.root_dir)
            end
        end
    end
end
