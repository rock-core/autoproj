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

            def import(options = Hash.new)
                importer.import(self, options)
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
            home_dir =
                begin Dir.home
                rescue ArgumentError
                end

            if home_dir
                rcfile = File.join(home_dir, '.autoprojrc')
                if File.file?(rcfile)
                    Kernel.load rcfile
                end
            end
        end

        def load_main_initrb(manifest = Autoproj.manifest)
            local_source = LocalPackageSet.new(manifest)
            Autoproj.load_if_present(local_source, local_source.local_dir, "init.rb")
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

            parser.on("--[no-]color", "enable or disable color in status messages (enabled by default)") do |flag|
                Autoproj::CmdLine.color = flag
                Autobuild.color = flag
            end

            parser.on("--[no-]progress", "enable or disable progress display (enabled by default)") do |flag|
                Autobuild.progress_display_enabled = flag
            end
        end

        def resolve_selection(user_selection, options = Hash.new)
            options = Kernel.validate_options options,
                recursive: true,
                ignore_non_imported_packages: false

            resolved_selection = CmdLine.
                resolve_user_selection(user_selection, filter: false)
            if options[:ignore_non_imported_packages]
                manifest.each_autobuild_package do |pkg|
                    if !File.directory?(pkg.srcdir)
                        manifest.ignore_package(pkg.name)
                    end
                end
            end
            resolved_selection.filter_excluded_and_ignored_packages(manifest)

            packages =
                if options[:recursive]
                    CmdLine.import_packages(
                        resolved_selection,
                        warn_about_ignored_packages: false)
                else
                    resolved_selection.to_a
                end

            packages
        end

        extend Tools
    end
    end
end

