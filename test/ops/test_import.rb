require 'autoproj/test'

module Autoproj
    module Ops
        describe Import do
            attr_reader :ops
            before do
                ws_create
                ws_define_package :cmake, '0'
                ws_define_package :cmake, '1'
                ws_define_package :cmake, '11'
                ws_define_package :cmake, '12'
                ws.manifest.exclude_package '0', 'reason0'
                @ops = Import.new(ws)
            end

            let(:revdeps) { Hash['0' => %w{1}, '1' => %w{11 12}] }

            describe "#mark_exclusion_along_revdeps" do
                it "marks all packages that depend on an excluded package as excluded" do
                    ops.mark_exclusion_along_revdeps('0', revdeps)
                    assert ws.manifest.excluded?('1')
                    assert ws.manifest.excluded?('11')
                    assert ws.manifest.excluded?('12')
                end
                it "stores the dependency chain in the exclusion reason for links of more than one hop" do
                    ops.mark_exclusion_along_revdeps('0', revdeps)
                    assert_match(/11>1>0/, ws.manifest.exclusion_reason('11'))
                    assert_match(/12>1>0/, ws.manifest.exclusion_reason('12'))
                end
                it "stores the original package's reason in the exclusion reason" do
                    ops.mark_exclusion_along_revdeps('0', revdeps)
                    assert_match(/reason0/, ws.manifest.exclusion_reason('1'))
                    assert_match(/reason0/, ws.manifest.exclusion_reason('11'))
                    assert_match(/reason0/, ws.manifest.exclusion_reason('12'))
                end
                it "ignores packages that are already excluded" do
                    ws.manifest.exclude_package '11', 'reason11'
                    flexmock(ws.manifest).should_receive(:exclude_package).with(->(name) { name != '11' }, any).twice.pass_thru
                    ops.mark_exclusion_along_revdeps('0', revdeps)
                end
            end

            describe "#import_selected_packages" do
                attr_reader :base_cmake
                before do
                    @base_cmake = ws_define_package :cmake, 'base/cmake'
                    mock_vcs(base_cmake)
                    flexmock(ws.os_package_installer).should_receive(:install).by_default
                end

                def mock_vcs(package, type: :git, url: 'https://github.com', interactive: false)
                    package.vcs = VCSDefinition.from_raw(type: type, url: url)
                    package.autobuild.importer = flexmock(interactive?: interactive)
                end

                def mock_selection(*packages)
                    mock = flexmock
                    mock.should_receive(:each_source_package_name).
                        and_return(packages.map(&:name))
                    mock
                end
                it "skips non-imported packages and returns them if pass_non_imported_packages is true" do
                    ws_setup_package_dirs(base_cmake, create_srcdir: false)
                    assert_equal Set[base_cmake],
                        ops.import_selected_packages(mock_selection(base_cmake), [], pass_non_imported_packages: true)
                end
                it "does not load information nor calls post-import blocks for non-imported packages" do
                    ws_setup_package_dirs(base_cmake, create_srcdir: false)
                    flexmock(ws.manifest).should_receive(:load_package_manifest).
                        with('processed').never
                    flexmock(Autoproj).should_receive(:each_post_import_block).never
                    ops.import_selected_packages(mock_selection(base_cmake), [], 
                                                 pass_non_imported_packages: true)
                end
                it "imports the given package" do
                    flexmock(base_cmake.autobuild).should_receive(:import).once
                    flexmock(ws.os_package_installer).should_receive(:install)
                    ops.import_selected_packages(mock_selection(base_cmake), [])
                end
                it "installs a missing VCS package" do
                    flexmock(base_cmake.autobuild).should_receive(:import).once
                    flexmock(ws.os_package_installer).should_receive(:install).
                        with([:git], Hash).once
                    ops.import_selected_packages(mock_selection(base_cmake), [])
                end
                it "queues the package's dependencies after it loaded the manifest" do
                    base_depends = ws_define_package :cmake, 'base/depends'
                    mock_vcs(base_depends)
                    flexmock(base_cmake.autobuild).should_receive(:import).once.globally.ordered
                    flexmock(ws.manifest).should_receive(:load_package_manifest).
                        with('base/cmake').once.globally.ordered.
                        and_return do
                            base_cmake.autobuild.depends_on 'base/depends'
                        end
                    flexmock(base_depends.autobuild).should_receive(:import).once.globally.ordered
                    flexmock(ws.manifest).should_receive(:load_package_manifest).
                        with('base/depends').once.globally.ordered

                    ops.import_selected_packages(mock_selection(base_cmake), [])
                end
                it "does not attempt to install the 'local' VCS" do
                    mock_vcs(base_cmake, type: 'local', url: '/path/to/dir')
                    base_cmake.autobuild.importer = nil
                    flexmock(ws.os_package_installer).should_receive(:install).never
                    ops.import_selected_packages(mock_selection(base_cmake), [])
                end
                it "does not attempt to install the 'none' VCS" do
                    mock_vcs(base_cmake, type: 'none')
                    base_cmake.autobuild.importer = nil
                    flexmock(ws.os_package_installer).should_receive(:install).never
                    ops.import_selected_packages(mock_selection(base_cmake), [])
                end
                it "does not attempt to install the VCS packages if install_vcs_packages is false" do
                    mock_vcs(base_cmake)
                    flexmock(base_cmake.autobuild).should_receive(:import)
                    flexmock(ws.os_package_installer).should_receive(:install).never
                    ops.import_selected_packages(mock_selection(base_cmake), [], install_vcs_packages: nil)
                end
                it "sets the retry_count on the non-interactive packages before it calls #import on them" do
                    mock_vcs(base_cmake)
                    retry_count = flexmock
                    flexmock(base_cmake.autobuild.importer).should_receive(:retry_count=).with(retry_count).
                        once.globally.ordered
                    flexmock(base_cmake.autobuild.importer).should_receive(:import).
                        once.globally.ordered
                    ops.import_selected_packages(mock_selection(base_cmake), [], retry_count: retry_count)

                end
                it "sets the retry_count on the interactive packages before it calls #import on them" do
                    mock_vcs(base_cmake, interactive: true)
                    retry_count = flexmock
                    flexmock(base_cmake.autobuild.importer).should_receive(:retry_count=).with(retry_count).
                        once.globally.ordered
                    flexmock(base_cmake.autobuild.importer).should_receive(:import).
                        once.globally.ordered
                    ops.import_selected_packages(mock_selection(base_cmake), [], retry_count: retry_count)
                end

                it "fails if a package has no importer and is not present on disk" do
                    mock_vcs(base_cmake, type: 'none')
                    srcdir = File.join(ws.root_dir, 'package')
                    base_cmake.autobuild.srcdir = srcdir
                    base_cmake.autobuild.importer = nil
                    flexmock(ws.os_package_installer).should_receive(:install).never
                    e = assert_raises(ConfigError) do
                        ops.import_selected_packages(mock_selection(base_cmake), [])
                    end
                    assert_equal "base/cmake has no VCS, but is not checked out in #{srcdir}",
                        e.message
                end
                it "passes on packages that have no importers but are present on disk" do
                    mock_vcs(base_cmake, type: 'none')
                    FileUtils.mkdir_p(base_cmake.autobuild.srcdir = File.join(ws.root_dir, 'package'))
                    base_cmake.autobuild.importer = nil
                    flexmock(ops).should_receive(:post_package_import).
                        with(any, any, base_cmake.autobuild, any).
                        once
                    ops.import_selected_packages(mock_selection(base_cmake), [])
                end
                it "processes all non-interactive importers in parallel and then the interactive ones in the main thread" do
                    mock_vcs(base_cmake, interactive: true)
                    non_interactive = ws_define_package :cmake, 'non/interactive'
                    mock_vcs(non_interactive, interactive: false)
                    main_thread = Thread.current
                    flexmock(non_interactive.autobuild).should_receive(:import).once.globally.ordered.
                        with(hsh(allow_interactive: false)).
                        and_return do
                            if Thread.current == main_thread
                                flunk("expected the non-interactive package to be imported outside the main thread")
                            end
                        end
                    flexmock(ops).should_receive(:post_package_import).
                        with(any, any, non_interactive.autobuild, any).
                        once.globally.ordered
                    flexmock(base_cmake.autobuild).should_receive(:import).once.globally.ordered.
                        with(hsh(allow_interactive: true)).
                        and_return do
                            if Thread.current != main_thread
                                flunk("expected the interactive package to be imported inside the main thread")
                            end
                        end
                    flexmock(ops).should_receive(:post_package_import).
                        with(any, any, base_cmake.autobuild, any).
                        once.globally.ordered

                    ops.import_selected_packages(mock_selection(non_interactive, base_cmake), [])
                end

                it "retries importers that raise InteractionRequired in the non-interactive section within the interactive one" do
                    mock_vcs(base_cmake, interactive: false)
                    main_thread = Thread.current
                    flexmock(base_cmake.autobuild).should_receive(:import).once.globally.ordered.
                        with(hsh(allow_interactive: false)).
                        and_raise(Autobuild::InteractionRequired)
                    flexmock(base_cmake.autobuild).should_receive(:import).once.globally.ordered.
                        with(hsh(allow_interactive: true)).
                        and_return do
                            assert_equal main_thread, Thread.current, "expected interactive imports to be called in the main thread"
                        end

                    flexmock(ops).should_receive(:post_package_import).
                        with(any, any, base_cmake.autobuild, any).
                        once.globally.ordered
                    ops.import_selected_packages(mock_selection(base_cmake), [])
                end

                it "terminates the import if an import failed and ignore_errors is false" do
                    mock_vcs(base_cmake)
                    base_types = ws_define_package :cmake, 'base/types'
                    mock_vcs(base_types)
                    flexmock(base_cmake.autobuild).should_receive(:import).once.
                        and_raise(ArgumentError)
                    flexmock(base_types.autobuild).should_receive(:import).never
                    assert_raises(Import::ImportFailed) do
                        ops.import_selected_packages(mock_selection(base_cmake, base_types), [], ignore_errors: false, parallel_import_level: 1)
                    end
                end

                it "does attempt to import the other packages if an import failed and ignore_errors is true" do
                    mock_vcs(base_cmake)
                    base_types = ws_define_package :cmake, 'base/types'
                    mock_vcs(base_types)
                    flexmock(base_cmake.autobuild).should_receive(:import).once.
                        and_raise(ArgumentError)
                    flexmock(base_types.autobuild).should_receive(:import).once
                    assert_raises(Import::ImportFailed) do
                        ops.import_selected_packages(mock_selection(base_cmake, base_types), [], ignore_errors: true, parallel_import_level: 1)
                    end
                end

                it "does not post-processes a package that failed to import" do
                    mock_vcs(base_cmake)
                    base_types = ws_define_package :cmake, 'base/types'
                    mock_vcs(base_types)
                    flexmock(base_cmake.autobuild).should_receive(:import).once.
                        and_raise(ArgumentError)
                    flexmock(ops).should_receive(:post_package_import).never
                    assert_raises(Import::ImportFailed) do
                        ops.import_selected_packages(mock_selection(base_cmake), [])
                    end
                end

                it "does not wait on a package for which it failed to queue the work" do
                    mock_vcs(base_cmake)
                    flexmock(ops).should_receive(:queue_import_work).and_raise(ArgumentError)
                    assert_raises(ArgumentError) do
                        ops.import_selected_packages(mock_selection(base_cmake), [])
                    end
                end
            end

            describe "#finalize_package_load" do
                it "does not load information nor calls post-import blocks for processed packages" do
                    processed = ws_add_package_to_layout :cmake, 'processed'
                    ws_setup_package_dirs(processed)
                    flexmock(ws.manifest).should_receive(:load_package_manifest).
                        with('processed').never
                    flexmock(Autoproj).should_receive(:each_post_import_block).never
                    ops.finalize_package_load([processed])
                end
                it "does not load information nor calls post-import blocks for packages that are not present on disk" do
                    package = ws_add_package_to_layout :cmake, 'package'
                    ws_setup_package_dirs(package, create_srcdir: false)
                    flexmock(ws.manifest).should_receive(:load_package_manifest).
                        with('processed').never
                    flexmock(Autoproj).should_receive(:each_post_import_block).never
                    ops.finalize_package_load([])
                end

                it "loads the information for all packages in the layout that have not been processed" do
                    ws_add_package_to_layout :cmake, 'not_processed'
                    flexmock(ws.manifest).should_receive(:load_package_manifest).
                        with('not_processed').once
                    ops.finalize_package_load([])
                end
                it "calls post-import blocks for all packages in the layout that have not been processed" do
                    not_processed = ws_add_package_to_layout :cmake, 'not_processed'
                    flexmock(Autoproj).should_receive(:each_post_import_block).
                        with(not_processed.autobuild, Proc).once
                    ops.finalize_package_load([])
                end
                it "ignores not processed packages from the layout whose srcdir is not present" do
                    not_processed = ws_add_package_to_layout :cmake, 'not_processed'
                    not_processed.autobuild.srcdir = '/does/not/exist'
                    flexmock(ws.manifest).should_receive(:load_package_manifest).
                        with('not_processed').never
                    ops.finalize_package_load([])
                end
            end
        end
    end
end

