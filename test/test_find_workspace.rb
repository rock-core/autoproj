require "autoproj/test"
require "tmpdir"

describe Autoproj do
    describe ".find_v2_root_dir" do
        attr_reader :workspace_root, :testdir
        before do
            @testdir = make_tmpdir
            @workspace_root = File.join(testdir, "path", "to", "workspace")
            FileUtils.mkdir_p File.join(workspace_root, ".autoproj")
            FileUtils.touch File.join(workspace_root, ".autoproj", "config.yml")
            FileUtils.mkdir_p File.join(workspace_root, "with", "subdir")
        end

        it "returns a parent path that contain an .autoproj directory" do
            assert_equal workspace_root, Autoproj.find_v2_root_dir(File.join(workspace_root, "with", "subdir"), "")
            assert_equal workspace_root, Autoproj.find_v2_root_dir(workspace_root, "")
        end
        it "expands relative paths properly" do
            Dir.chdir(File.join(workspace_root, "with")) do
                assert_equal workspace_root, Autoproj.find_v2_root_dir("./subdir", "")
                assert_equal workspace_root, Autoproj.find_v2_root_dir("subdir", "")
            end
        end
        it "resolves a config file value if a config file is found" do
            actual_workspace = File.join(testdir, "actual_workspace")
            FileUtils.mkdir_p File.join(actual_workspace, ".autoproj")
            FileUtils.touch File.join(actual_workspace, ".autoproj", "config.yml")
            File.open(File.join(workspace_root, ".autoproj", "config.yml"), "w") do |io|
                io.puts "c: #{actual_workspace}"
            end
            assert_equal actual_workspace, Autoproj.find_v2_root_dir(workspace_root, "c")
        end
        it "raises if the config value does not point to a valid v2 workspace" do
            File.open(File.join(workspace_root, ".autoproj", "config.yml"), "w") do |io|
                io.puts "c: #{testdir}"
            end
            assert_raises(ArgumentError) do
                Autoproj.find_v2_root_dir(workspace_root, "c")
            end
        end
        it "handles a config file that points to itself" do
            File.open(File.join(workspace_root, ".autoproj", "config.yml"), "w") do |io|
                io.puts "c: #{workspace_root}"
            end
            assert_equal workspace_root, Autoproj.find_v2_root_dir(workspace_root, "c")
        end
        it "returns the found path if a config file is found but it does not contain the required field" do
            File.open(File.join(workspace_root, ".autoproj", "config.yml"), "w") do |io|
                io.puts "c: #{workspace_root}"
            end
            assert_equal workspace_root, Autoproj.find_v2_root_dir(workspace_root, "another_field")
        end
        it "returns falsey if it reaches the root path" do
            assert !Autoproj.find_v2_root_dir(testdir, "")
        end
        it "returns nil if the path does not exist" do
            assert !Autoproj.find_v2_root_dir("/does/not/exist", "")
        end
    end
end
