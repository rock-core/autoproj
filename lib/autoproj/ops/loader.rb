module Autoproj
    module Ops
    class Loader
        # @return [Array<String>] information about what is being loaded
        attr_reader :file_stack

        def initialize
            @file_stack = Array.new
        end

        def in_package_set(pkg_set, path)
            @file_stack.push([pkg_set, File.expand_path(path).gsub(/^#{Regexp.quote(Autoproj.root_dir)}\//, '')])
            yield
        ensure
            @file_stack.pop
        end

        def filter_load_exception(error, package_set, path)
            raise error if Autoproj.verbose
            rx_path = Regexp.quote(path)
            if error_line = error.backtrace.find { |l| l =~ /#{rx_path}/ }
                if line_number = Integer(/#{rx_path}:(\d+)/.match(error_line)[1])
                    line_number = "#{line_number}:"
                end

                if package_set.local?
                    raise ConfigError.new(path), "#{path}:#{line_number} #{error.message}", error.backtrace
                else
                    raise ConfigError.new(path), "#{File.basename(path)}(package_set=#{package_set.name}):#{line_number} #{error.message}", error.backtrace
                end
            else
                raise error
            end
        end

        # Returns the information about the file that is currently being loaded
        #
        # The return value is [package_set, path], where +package_set+ is the
        # PackageSet instance and +path+ is the path of the file w.r.t. the autoproj
        # root directory
        def current_file
            if file = @file_stack.last
                file
            else raise ArgumentError, "not in a #in_package_set context"
            end
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
            in_package_set(pkg_set, File.expand_path(path).gsub(/^#{Regexp.quote(Autoproj.root_dir)}\//, '')) do
                begin
                    Kernel.load path
                rescue Interrupt
                    raise
                rescue ConfigError => e
                    raise
                rescue Exception => e
                    filter_load_exception(e, pkg_set, path)
                end
            end
        end

        # Load a definition file from a package set if the file is present
        #
        # (see load)
        def load_if_present(pkg_set, *path)
            path = File.join(*path)
            if File.file?(path)
                load(pkg_set, *path)
            end
        end
    end

    # Singleton object that maintains the loading state
    #
    # Note that it is here hopefully temporarily. All the Ops classes should
    # have their loader object given at construction time
    def self.loader
        @loader ||= Loader.new
    end
    end
end

