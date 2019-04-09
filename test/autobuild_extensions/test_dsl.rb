require 'autoproj/test'

module Autoproj
    describe "package_handler_for" do
        before do
            @dir = make_tmpdir
            FileUtils.mkdir_p File.join(@dir, "a", "b", "c")
        end

        describe "orogen package" do
            it "returns the directory if it contains an orogen file" do
                FileUtils.touch File.join(@dir, "a", "test.orogen")
                assert_equal ['orogen_package', File.join(@dir, "a")],
                    Autoproj.package_handler_for(File.join(@dir, "a"))
            end
        end

        describe "CMake detection" do
            before do
                File.open(File.join(@dir, "a", "CMakeLists.txt"), 'w') do |io|
                    io.puts "project(TEST)"
                end
                FileUtils.touch File.join(@dir, "a", "b", "CMakeLists.txt")
                FileUtils.touch File.join(@dir, "a", "b", "c", "CMakeLists.txt")
            end

            it "returns the toplevel directory that has a CMakeLists that defines a project" do
                assert_equal ['cmake_package', File.join(@dir, "a")],
                    Autoproj.package_handler_for(File.join(@dir, "a", "b", "c"))
            end

            it "falls back to the toplevel CMakeLists.txt" do
                FileUtils.rm_f File.join(@dir, "a", "CMakeLists.txt")
                FileUtils.touch File.join(@dir, "a", "CMakeLists.txt")
                assert_equal ['cmake_package', File.join(@dir, "a")],
                    Autoproj.package_handler_for(File.join(@dir, "a", "b", "c"))
            end

            it "returns catkin_package if the directory also contains package.xml" do
                FileUtils.touch File.join(@dir, "a", "package.xml")
                assert_equal ['catkin_package', File.join(@dir, "a")],
                    Autoproj.package_handler_for(File.join(@dir, "a", "b", "c"))
            end

            it "returns cmake_package if the directory contains both manifest.xml and package.xml" do
                FileUtils.touch File.join(@dir, "a", "package.xml")
                FileUtils.touch File.join(@dir, "a", "manifest.xml")
                assert_equal ['cmake_package', File.join(@dir, "a")],
                    Autoproj.package_handler_for(File.join(@dir, "a", "b", "c"))
            end
        end

        describe "autotools detection" do
            before do
                FileUtils.touch File.join(@dir, "a", "Makefile.am")
                FileUtils.touch File.join(@dir, "a", "b", "Makefile.am")
                FileUtils.touch File.join(@dir, "a", "b", "c", "Makefile.am")
            end

            it "return the given directory if it has a configure.ac" do
                dir = make_tmpdir
                FileUtils.touch File.join(dir, "configure.ac")
                assert_equal ['autotools_package', dir],
                    Autoproj.package_handler_for(dir)
            end
            it "return the given directory if it has a configure.in" do
                dir = make_tmpdir
                FileUtils.touch File.join(dir, "configure.in")
                assert_equal ['autotools_package', dir],
                    Autoproj.package_handler_for(dir)
            end
            it "returns the toplevel directory in which there is a configure.ac if the given directory has Makefile.am" do
                FileUtils.touch File.join(@dir, "a", "configure.ac")
                assert_equal ['autotools_package', File.join(@dir, "a")],
                    Autoproj.package_handler_for(File.join(@dir, "a", "b", "c"))
            end
            it "returns the toplevel directory in which there is a configure.in if the given directory has Makefile.am" do
                FileUtils.touch File.join(@dir, "a", "configure.in")
                assert_equal ['autotools_package', File.join(@dir, "a")],
                    Autoproj.package_handler_for(File.join(@dir, "a", "b", "c"))
            end
        end

        describe "ruby package" do
            it "returns the directory if it contains a Rakefile" do
                FileUtils.touch File.join(@dir, "a", "Rakefile")
                assert_equal ['ruby_package', File.join(@dir, "a")],
                    Autoproj.package_handler_for(File.join(@dir, "a"))
            end

            it "returns the directory if there are ruby files under lib/" do
                FileUtils.mkdir_p(File.join(@dir, "a", "lib"))
                FileUtils.touch(File.join(@dir, "a", "lib", "test.rb"))
                assert_equal ['ruby_package', File.join(@dir, "a")],
                    Autoproj.package_handler_for(File.join(@dir, "a"))
            end
        end

        describe "python package" do
            it "returns the directory if it contains setup.py" do
                FileUtils.touch File.join(@dir, "a", "setup.py")
                assert_equal ['python_package', File.join(@dir, "a")],
                    Autoproj.package_handler_for(File.join(@dir, "a"))
            end

            it "returns the directory if there are python files under <basename>/" do
                FileUtils.mkdir_p(File.join(@dir, "a", "a"))
                FileUtils.touch(File.join(@dir, "a", "a", "test.py"))
                assert_equal ['python_package', File.join(@dir, "a")],
                    Autoproj.package_handler_for(File.join(@dir, "a"))
            end
        end

        it "returns nil if nothing is detected" do
            assert_nil Autoproj.package_handler_for(@dir)
        end
    end
end
