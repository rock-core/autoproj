module Autoproj
    module Ops
        class Loader
            # The path w.r.t. which we should resolve relative paths
            #
            # @return [String]
            attr_reader :root_dir
            # @return [Array<String>] information about what is being loaded
            attr_reader :file_stack

            def initialize(root_dir)
                @root_dir = root_dir
                @file_stack = Array.new
                @loaded_autobuild_files = Set.new
            end

            def in_package_set(pkg_set, path)
                path = File.expand_path(path, root_dir) if path
                @file_stack.push([pkg_set, path])
                yield
            ensure
                @file_stack.pop
            end

            def filter_load_exception(error, package_set, path)
                raise error if Autoproj.verbose

                rx_path = Regexp.quote(path)
                unless (error_line = error.backtrace.find { |l| l =~ /#{rx_path}/ })
                    raise error
                end

                if (line_number = Integer(/#{rx_path}:(\d+)/.match(error_line)[1]))
                    line_number = "#{line_number}:"
                end

                if package_set.local?
                    raise ConfigError.new(path),
                          "#{path}:#{line_number} #{error.message}", error.backtrace
                else
                    raise ConfigError.new(path),
                          "#{File.basename(path)}(package_set=#{package_set.name}):"\
                          "#{line_number} #{error.message}", error.backtrace
                end
            end

            # Returns the information about the file that is currently being loaded
            #
            # The return value is [package_set, path], where +package_set+ is the
            # PackageSet instance and +path+ is the path of the file w.r.t. the autoproj
            # root directory
            def current_file
                unless (file = @file_stack.last)
                    raise ArgumentError, "not in a #in_package_set context"
                end

                file
            end

            # The PackageSet object representing the package set that is currently being
            # loaded
            def current_package_set
                current_file.first
            end

            # Load a definition file from a package set
            #
            # If any error is detected, the backtrace will be filtered so that it is
            # easier to understand by the user. Moreover, if +source+ is non-nil, the
            # package set name will be mentionned.
            #
            # @param [PackageSet] pkg_set
            # @param [Array<String>] path
            def load(pkg_set, *path)
                path = File.join(*path)
                relative_path =
                    File.expand_path(path).gsub(/^#{Regexp.quote(root_dir)}\//, "")
                in_package_set(pkg_set, relative_path) do
                    Kernel.load path
                rescue Interrupt
                    raise
                rescue ConfigError => e
                    raise
                rescue Exception => e
                    filter_load_exception(e, pkg_set, path)
                end
            end

            # Load a definition file from a package set if the file is present
            #
            # (see load)
            def load_if_present(pkg_set, *path)
                path = File.join(*path)
                load(pkg_set, *path) if File.file?(path)
            end

            def import_autobuild_file(package_set, path)
                return if @loaded_autobuild_files.include?(path)

                load(package_set, path)
                @loaded_autobuild_files << path
            end
        end

        # @deprecated use Autoproj.workspace, or better make sure all ops classes
        #   get their own workspace object as argument
        def self.loader
            Autoproj.workspace
        end
    end
end
