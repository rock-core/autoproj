module Autoproj
    module Ops
    module Tools
        # Data structure used to use autobuild importers without a package, to
        # import configuration data.
        #
        # It has to match the interface of Autobuild::Package that is relevant
        # for importers
        class FakePackage < Autobuild::Package
            attr_reader :srcdir
            attr_reader :importer

            # Used by the autobuild importers
            attr_accessor :updated

            def autoproj_name
                name
            end

            def initialize(text_name, srcdir, importer = nil)
                super(text_name)
                @srcdir = srcdir
                @importer = importer
                @@packages.delete(text_name)
            end

            def import(only_local = false)
                importer.import(self, only_local)
            end

            def add_stat(*args)
            end
        end

        # Creates an autobuild package whose job is to allow the import of a
        # specific repository into a given directory.
        #
        # +vcs+ is the VCSDefinition file describing the repository, +text_name+
        # the name used when displaying the import progress, +pkg_name+ the
        # internal name used to represent the package and +into+ the directory
        # in which the package should be checked out.
        def create_autobuild_package(vcs, text_name, into)
            importer     = vcs.create_autobuild_importer
            FakePackage.new(text_name, into, importer)

        rescue Autobuild::ConfigException => e
            raise ConfigError.new, "cannot import #{text_name}: #{e.message}", e.backtrace
        end

        def load_autoprojrc
            # Load the user-wide autoproj RC file
            if home_dir = Dir.home
                rcfile = File.join(home_dir, '.autoprojrc')
                if File.file?(rcfile)
                    Kernel.load rcfile
                end
            end
        end

        def common_options(parser)
            parser.on '--verbose' do
                Autoproj.verbose  = true
                Autobuild.verbose = true
                Rake.application.options.trace = false
                Autobuild.debug = false
            end

            parser.on '--debug' do
                Autoproj.verbose  = true
                Autobuild.verbose = true
                Rake.application.options.trace = true
                Autobuild.debug = true
            end
        end

        extend Tools
    end
    end
end

