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

        # This performs the very basic setup that should be done once, and only
        # once, in an autoproj-based CLI tool
        def basic_setup
            Encoding.default_internal = Encoding::UTF_8
            Encoding.default_external = Encoding::UTF_8

            Autobuild::Reporting << Autoproj::Reporter.new
            Autobuild::Package.clear
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
            Autoproj.warn_deprecated __method__, "use workspace.load_autoprojrc instead"
            Autoproj.workspace.load_autoprojrc
        end

        def load_main_initrb(*args)
            Autoproj.warn_deprecated __method__, "use workspace.load_main_initrb instead"
            Autoproj.workspace.load_main_initrb
        end

        def handle_common_options(options)
            options, remaining = filter_options options,
                silent: false,
                verbose: false,
                debug: false,
                color: true,
                progress: true

            Autoproj.silent = options[:silent]
            if options.delete(:verbose)
                Autoproj.verbose  = true
                Autobuild.verbose = true
                Rake.application.options.trace = false
                Autobuild.debug = false
            end

            if options[:debug]
                Autoproj.verbose  = true
                Autobuild.verbose = true
                Rake.application.options.trace = true
                Autobuild.debug = true
            end

            Autobuild.color =
                Autoproj::CmdLine.color = options[:color]

            Autobuild.progress_display_enabled = options[:progress]
            remaining
        end

        def common_options(parser)
            parser.on '--silent' do
                Autoproj.silent = true
            end

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

        def resolve_selection(manifest, user_selection, options = Hash.new)
            options = Kernel.validate_options options,
                checkout_only: true,
                only_local: false,
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
                        checkout_only: options[:checkout_only],
                        only_local: options[:only_local],
                        warn_about_ignored_packages: false)
                else
                    resolved_selection.to_a
                end

            return packages, resolved_selection
        end

        extend Tools
    end
    end
end

