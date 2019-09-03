require 'autoproj/test'
require 'timecop'

module Autoproj
    module Ops
        describe Import do
            attr_reader :ops
            before do
                ws_create
                @pkg0 = ws_define_package :cmake, '0'
                @pkg1 = ws_define_package :cmake, '1'
                @pkg11 = ws_define_package :cmake, '11'
                @pkg12 = ws_define_package :cmake, '12'
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

            describe "#import_packages" do
                before do
                    @selection = PackageSelection.new
                    flexmock(ws.manifest)

                    Timecop.freeze
                end

                after do
                    Timecop.return
                end

                it "loads information about non-excluded packages that are present on disk but are not required by the build" do
                    flexmock(ops).should_receive(:import_selected_packages).
                        and_return([[@pkg1], []])

                    ws.manifest.should_receive(:load_package_manifest).once.with('11')
                    ops.should_receive(:process_post_import_blocks).once.with(@pkg11.autobuild)
                    ws.manifest.should_receive(:load_package_manifest).once.with('12')
                    ops.should_receive(:process_post_import_blocks).once.with(@pkg12.autobuild)
                    ops.import_packages(@selection)
                end

                it "exports a report for the processed packages" do
                    tmpdir = make_tmpdir
                    report_path = File.join(tmpdir, 'report.json')
                    ops = Import.new(ws, report_path: report_path)
                    flexmock(ops).should_receive(:import_selected_packages).
                        and_return([[@pkg1], []])

                    ws.manifest.should_receive(:load_package_manifest) # to shut up warnings
                    ops.import_packages(@selection)
                    json = JSON.load(File.read(report_path))
                    assert_equal({
                        'import_report' => {
                            'timestamp' => Time.now.to_s,
                            'packages' => {
                                '1' => { 'invoked' => false, 'success' => false }
                            }
                        }
                    }, json)
                end

                it "exports a report on failure" do
                    tmpdir = make_tmpdir
                    report_path = File.join(tmpdir, 'report.json')
                    ops = Import.new(ws, report_path: report_path)
                    e = Class.new(RuntimeError)
                    flexmock(ops).should_receive(:import_selected_packages).
                        and_return([[@pkg1], [e]])

                    ws.manifest.should_receive(:load_package_manifest)
                    assert_raises(e) do
                        ops.import_packages(@selection) # to shut up warnings
                    end
                    json = JSON.load(File.read(report_path))
                    assert_equal({
                        'import_report' => {
                            'timestamp' => Time.now.to_s,
                            'packages' => {
                                '1' => { 'invoked' => false, 'success' => false }
                            }
                        }
                    }, json)
                end

                describe "auto_exclude: true" do
                    it "excludes packages that have failed to load" do
                        flexmock(ops).should_receive(:import_selected_packages).
                            and_return([[@pkg1], []])

                        ws.manifest.should_receive(:load_package_manifest).once.with('11').
                            and_raise(ArgumentError)
                        ws.manifest.should_receive(:load_package_manifest).once.with('12')
                        ops.should_receive(:process_post_import_blocks).once.with(@pkg12.autobuild)
                        ops.import_packages(@selection, auto_exclude: true)
                        assert ws.manifest.excluded?('11')
                    end
                end

                it 'installs internal dependencies for all processed packages' do
                    flexmock(ops).should_receive(:import_selected_packages).
                        and_return([[@pkg1], []])

                    flexmock(ops).should_receive(:install_internal_dependencies_for).with(@pkg1).once
                    ops.import_packages(@selection)
                end
            end

            describe "#create_report" do
                before do
                    @ws = ws_create
                    @ops = Import.new(ws, report_path: @ws.import_report_path)
                    @pkg1 = ws_define_package :cmake, 'pkg1'
                    @pkg2 = ws_define_package :cmake, 'pkg2'
                    @pkg3 = ws_define_package :cmake, 'pkg3'

                    @pkg1object = ws.manifest.find_autobuild_package('pkg1')
                    @pkg2object = ws.manifest.find_autobuild_package('pkg2')
                    @pkg3object = ws.manifest.find_autobuild_package('pkg3')

                    Timecop.freeze

                    flexmock(@pkg1object)
                    @pkg1object.should_receive(import_invoked?: true)
                    @pkg1object.should_receive(imported?: true)

                    flexmock(@pkg2object)
                    @pkg2object.should_receive(import_invoked?: true)
                    @pkg2object.should_receive(imported?: false)

                    flexmock(@pkg3object)
                    @pkg3object.should_receive(import_invoked?: false)
                    @pkg3object.should_receive(imported?: false)
                end

                after do
                    Timecop.return
                end

                it "works even if given no packages to work on" do
                    @ops.create_report([])
                    json = read_report
                    assert_equal({
                        'import_report' => {
                            'timestamp' => Time.now.to_s,
                            'packages' => {}
                        }
                    }, json)
                end

                it "works with just one successful package" do
                    @ops.create_report(['pkg1'])
                    json = read_report
                    assert_equal({
                        'import_report' => {
                            'timestamp' => Time.now.to_s,
                            'packages' => {
                                'pkg1' => { 'invoked' => true, 'success' => true },
                            }
                        }
                    }, json)
                end

                it "works with just one failed package" do
                    @ops.create_report(['pkg2'])
                    json = read_report
                    assert_equal({
                        'import_report' => {
                            'timestamp' => Time.now.to_s,
                            'packages' => {
                                'pkg2' => { 'invoked' => true, 'success' => false },
                            }
                        }
                    }, json)
                end


                it "exports the status of several given packages" do
                    @ops.create_report(['pkg1','pkg2', 'pkg3'])
                    json = read_report
                    assert_equal({
                        'import_report' => {
                            'timestamp' => Time.now.to_s,
                            'packages' => {
                                'pkg1' => { 'invoked' => true, 'success' => true },
                                'pkg2' => { 'invoked' => true, 'success' => false },
                                'pkg3' => { 'invoked' => false, 'success' => false }
                            }
                        }
                    }, json)
                end

                def read_report
                    data = File.read(@ws.import_report_path)
                    JSON.parse(data)
                end
            end

            describe '#install_internal_dependencies_for' do
                it 'installs internal dependencies for the given packages' do
                    flexmock(@pkg0.autobuild).should_receive(:internal_dependencies).and_return(['dep1'])
                    flexmock(@pkg1.autobuild).should_receive(:internal_dependencies).and_return(['dep2'])
                    flexmock(ws).should_receive(:install_os_packages).with(%w[dep1 dep2], all: nil).once
                    ops.install_internal_dependencies_for(@pkg0, @pkg1)
                end
            end

            describe "#import_selected_packages" do
                attr_reader :base_cmake
                before do
                    @base_cmake = ws_define_package :cmake, 'base/cmake'
                    mock_vcs(base_cmake)
                    flexmock(ws.os_package_installer).should_receive(:install).by_default
                end

                describe "non_imported_packages: :ignore" do
                    it "adds non-imported packages to the ignores" do
                        ws_setup_package_dirs(base_cmake, create_srcdir: false)
                        ops.import_selected_packages(
                            mock_selection(base_cmake), non_imported_packages: :ignore)
                        assert ws.manifest.ignored?('base/cmake')
                    end
                    it "skips the import of non-imported packages and does not return them" do
                        ws_setup_package_dirs(base_cmake, create_srcdir: false)
                        assert_equal [Set[], []],
                            ops.import_selected_packages(
                                mock_selection(base_cmake), non_imported_packages: :ignore)
                    end
                    it "does not load information nor calls post-import blocks for non-imported packages" do
                        ws_setup_package_dirs(base_cmake, create_srcdir: false)
                        flexmock(ws.manifest).should_receive(:load_package_manifest).
                            with('processed').never
                        flexmock(Autoproj).should_receive(:each_post_import_block).never
                        ops.import_selected_packages(mock_selection(base_cmake),
                                                     non_imported_packages: :return)
                    end
                end
                describe "non_imported_packages: :return" do
                    it "skips the import of non-imported packages and returns them" do
                        ws_setup_package_dirs(base_cmake, create_srcdir: false)
                        assert_equal [Set[base_cmake], []],
                            ops.import_selected_packages(mock_selection(base_cmake), non_imported_packages: :return)
                    end
                    it "does not load information nor calls post-import blocks for non-imported packages" do
                        ws_setup_package_dirs(base_cmake, create_srcdir: false)
                        flexmock(ws.manifest).should_receive(:load_package_manifest).
                            with('processed').never
                        flexmock(Autoproj).should_receive(:each_post_import_block).never
                        ops.import_selected_packages(mock_selection(base_cmake),
                                                     non_imported_packages: :return)
                    end
                end
                it "imports the given package" do
                    flexmock(base_cmake.autobuild).should_receive(:import).once
                    flexmock(ws.os_package_installer).should_receive(:install)
                    assert_equal [Set[base_cmake], []], ops.import_selected_packages(mock_selection(base_cmake))
                end
                it "installs a missing VCS package" do
                    flexmock(base_cmake.autobuild).should_receive(:import).once
                    flexmock(ws.os_package_installer).should_receive(:install).
                        with([:git], Hash).once
                    ops.import_selected_packages(mock_selection(base_cmake))
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

                    ops.import_selected_packages(mock_selection(base_cmake))
                end
                it "does not attempt to install the 'local' VCS" do
                    mock_vcs(base_cmake, type: 'local', url: '/path/to/dir')
                    base_cmake.autobuild.importer = nil
                    flexmock(ws.os_package_installer).should_receive(:install).never
                    ops.import_selected_packages(mock_selection(base_cmake))
                end
                it "does not attempt to install the 'none' VCS" do
                    mock_vcs(base_cmake, type: 'none')
                    base_cmake.autobuild.importer = nil
                    flexmock(ws.os_package_installer).should_receive(:install).never
                    ops.import_selected_packages(mock_selection(base_cmake))
                end
                it "does not attempt to install the VCS packages if install_vcs_packages is false" do
                    mock_vcs(base_cmake)
                    flexmock(base_cmake.autobuild).should_receive(:import)
                    flexmock(ws.os_package_installer).should_receive(:install).never
                    ops.import_selected_packages(mock_selection(base_cmake), install_vcs_packages: nil)
                end
                it "sets the retry_count on the non-interactive packages before it calls #import on them" do
                    mock_vcs(base_cmake)
                    retry_count = flexmock
                    flexmock(base_cmake.autobuild.importer).should_receive(:retry_count=).with(retry_count).
                        once.globally.ordered
                    flexmock(base_cmake.autobuild.importer).should_receive(:import).
                        once.globally.ordered
                    ops.import_selected_packages(mock_selection(base_cmake), retry_count: retry_count)

                end
                it "sets the retry_count on the interactive packages before it calls #import on them" do
                    mock_vcs(base_cmake, interactive: true)
                    retry_count = flexmock
                    flexmock(base_cmake.autobuild.importer).should_receive(:retry_count=).with(retry_count).
                        once.globally.ordered
                    flexmock(base_cmake.autobuild.importer).should_receive(:import).
                        once.globally.ordered
                    ops.import_selected_packages(mock_selection(base_cmake), retry_count: retry_count)
                end

                it "fails if a package has no importer and is not present on disk" do
                    mock_vcs(base_cmake, type: 'none')
                    srcdir = File.join(ws.root_dir, 'package')
                    base_cmake.autobuild.srcdir = srcdir
                    base_cmake.autobuild.importer = nil
                    flexmock(ws.os_package_installer).should_receive(:install).never
                    failure = assert_raises(ConfigError) do
                        ops.import_selected_packages(mock_selection(base_cmake))
                    end
                    assert_equal "base/cmake has no VCS, but is not checked out in #{srcdir}",
                        failure.message
                end
                it "checks out packages that are not present on disk" do
                    mock_vcs(base_cmake, type: 'git', url: 'https://github.com')
                    base_cmake.autobuild.srcdir = File.join(ws.root_dir, 'package')
                    flexmock(base_cmake.autobuild.importer).should_receive(:import).
                        with(base_cmake.autobuild, Hash).once
                    flexmock(ops).should_receive(:post_package_import).
                        with(any, any, base_cmake, any, Hash).
                        once
                    ops.import_selected_packages(mock_selection(base_cmake))
                end
                it "passes on packages that have no importers but are present on disk" do
                    mock_vcs(base_cmake, type: 'none')
                    FileUtils.mkdir_p(base_cmake.autobuild.srcdir = File.join(ws.root_dir, 'package'))
                    base_cmake.autobuild.importer = nil
                    flexmock(ops).should_receive(:post_package_import).
                        with(any, any, base_cmake, any, Hash).
                        once
                    ops.import_selected_packages(mock_selection(base_cmake))
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
                        with(any, any, non_interactive, any, Hash).
                        once.globally.ordered
                    flexmock(base_cmake.autobuild).should_receive(:import).once.globally.ordered.
                        with(hsh(allow_interactive: true)).
                        and_return do
                            if Thread.current != main_thread
                                flunk("expected the interactive package to be imported inside the main thread")
                            end
                        end
                    flexmock(ops).should_receive(:post_package_import).
                        with(any, any, base_cmake, any, Hash).
                        once.globally.ordered

                    ops.import_selected_packages(mock_selection(non_interactive, base_cmake))
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
                        with(any, any, base_cmake, any, Hash).
                        once.globally.ordered
                    ops.import_selected_packages(mock_selection(base_cmake))
                end

                it "terminates the import if an import failed and keep_going is false" do
                    mock_vcs(base_cmake)
                    base_types = ws_define_package :cmake, 'base/types'
                    mock_vcs(base_types)
                    flexmock(base_cmake.autobuild).should_receive(:import).once.
                        and_raise(error_t = Class.new(Exception))
                    flexmock(base_types.autobuild).should_receive(:import).never
                    _, failure =
                        ops.import_selected_packages(mock_selection(base_cmake, base_types),
                                                     keep_going: false, parallel: 1)
                    assert_equal 1, failure.size
                    assert_kind_of error_t, failure.first
                end

                it "does attempt to import the other packages if an import failed and keep_going is true" do
                    mock_vcs(base_cmake)
                    base_types = ws_define_package :cmake, 'base/types'
                    mock_vcs(base_types)
                    flexmock(base_cmake.autobuild).should_receive(:import).once.
                        and_raise(error_t = Class.new(Exception))
                    flexmock(base_types.autobuild).should_receive(:import).once
                    processed_packages, failure =
                        ops.import_selected_packages(mock_selection(base_cmake, base_types),
                                                     keep_going: true, parallel: 1)
                    assert_equal Set[base_cmake, base_types], processed_packages
                    assert_equal 1, failure.size
                    assert_kind_of error_t, failure.first
                end

                # warning: this is important because some package handlers may depend on its contents
                # to determine its internal dependencies
                it 'process post import blocks right after importing a package' do
                    mock_vcs(base_cmake, type: 'git', url: 'https://github.com')
                    flexmock(base_cmake.autobuild.importer).should_receive(:import).with(base_cmake.autobuild, Hash).once
                    flexmock(ops).should_receive(:process_post_import_blocks).once.with(base_cmake)
                    ops.import_selected_packages(mock_selection(base_cmake))
                end

                it "does not post-processes a package that failed to import" do
                    mock_vcs(base_cmake)
                    base_types = ws_define_package :cmake, 'base/types'
                    mock_vcs(base_types)
                    flexmock(base_cmake.autobuild).should_receive(:import).once.
                        and_raise(ArgumentError)
                    flexmock(ops).should_receive(:post_package_import).never
                    ops.import_selected_packages(mock_selection(base_cmake))
                end


                it "does not wait on a package for which it failed to queue the work" do
                    mock_vcs(base_cmake)
                    flexmock(ops).should_receive(:queue_import_work).and_raise(ArgumentError)
                    assert_raises(ArgumentError) do
                        ops.import_selected_packages(mock_selection(base_cmake))
                    end
                end

                it "raises if a package that is explicitely selected in the manifest depends on excluded packages" do
                    parent_pkg = ws_define_package :cmake, "parent"
                    ws_define_package :cmake, "child"
                    parent_pkg.autobuild.depends_on "child"

                    ws.manifest.initialize_from_hash(
                        'layout' => ['parent'],
                        'exclude_packages' => ['.*'])

                    selection = PackageSelection.new
                    selection.select("test", ['parent', 'child'], weak: true)
                    e = assert_raises(ExcludedSelection) do
                        ops.import_selected_packages(selection)
                    end
                    assert_equal "test is selected in the manifest or on the command line, but it expands to parent, which is excluded from the build: child is listed in the exclude_packages section of the manifest (dependency chain: parent>child)", e.message
                end

                it "raises if an already-imported package depends on an excluded package" do
                    parent_pkg = ws_define_package :cmake, "parent"
                    ws_define_package :cmake, "child"
                    parent_pkg.autobuild.depends_on "child"

                    selection = PackageSelection.new
                    selection.select("test", ['parent', 'child'], weak: true)
                    ws.manifest.add_exclusion('child', 'test')
                    e = assert_raises(ExcludedSelection) do
                        ops.import_selected_packages(selection)
                    end
                    assert_equal "test is selected in the manifest or on the command line, but it expands to parent, which is excluded from the build: test (dependency chain: parent>child)", e.message
                end

                it "raises if a package depends on an already-imported excluded package" do
                    parent_pkg = ws_define_package :cmake, "parent"
                    ws_define_package :cmake, "child"
                    parent_pkg.autobuild.depends_on "child"

                    selection = PackageSelection.new
                    selection.select("test", ['child', 'parent'], weak: true)
                    ws.manifest.add_exclusion('child', 'test')
                    e = assert_raises(ExcludedSelection) do
                        ops.import_selected_packages(selection)
                    end
                    assert_equal "test is selected in the manifest or on the command line, but it expands to parent, which is excluded from the build: test (dependency chain: parent>child)", e.message
                end

                describe "auto_exclude: true" do
                    attr_reader :base_types
                    before do
                        mock_vcs(base_cmake)
                        @base_types = ws_define_package :cmake, 'base/types'
                        mock_vcs(@base_types)
                        flexmock(@base_types.autobuild).should_receive(:import)
                        flexmock(ws.manifest).should_receive(:load_package_manifest).with('base/types')
                    end

                    it "auto-excludes a package that failed to import" do
                        flexmock(base_cmake.autobuild).should_receive(:import).once.
                            and_raise(ArgumentError)

                        selection = PackageSelection.new
                        selection.select 'test', ['base/types', 'base/cmake'], weak: true
                        ops.import_selected_packages(selection, auto_exclude: true)

                        assert ws.manifest.excluded?('base/cmake')
                        refute ws.manifest.excluded?('base/types')
                    end
                    it "auto-excludes a package whose manifest failed to load" do
                        flexmock(base_cmake.autobuild).should_receive(:import)
                        flexmock(ws.manifest).should_receive(:load_package_manifest).with('base/cmake').
                            and_raise(ArgumentError)

                        selection = PackageSelection.new
                        selection.select 'test', ['base/types', 'base/cmake'], weak: true
                        ops.import_selected_packages(selection, auto_exclude: true)

                        assert ws.manifest.excluded?('base/cmake')
                        refute ws.manifest.excluded?('base/types')
                    end
                end
            end

            describe '#post_package_import' do
                it 'enables dependencies needed by utilities enabled by a post-import block' do
                    pkg_manifest = PackageManifest.parse(@pkg1, <<~END_OF_XML)
                        <package><blabla_depend name="11" /></package>
                    END_OF_XML
                    @pkg1.autobuild.description = pkg_manifest
                    flexmock(ops).should_receive(:process_post_import_blocks).with(@pkg1)
                                 .and_return do
                                     flexmock(@pkg1).should_receive(:modes)
                                                    .and_return(['blabla'])
                                 end

                    ops.post_package_import(
                        PackageSelection.new, ws.manifest, @pkg1, Hash.new { Array.new })
                    assert @pkg1.autobuild.depends_on?('11')
                end

                it 'raises if a dependency from the manifest does not exist' do
                    xml = '<package><depend name="does_not_exist" /></package>'
                    pkg_manifest = PackageManifest.parse(@pkg1, xml,
                                                         path: '/path/to/manifest.xml')
                    @pkg1.autobuild.description = pkg_manifest
                    e = assert_raises(ConfigError) do
                        ops.post_package_import(
                            PackageSelection.new, ws.manifest, @pkg1, Hash.new { Array.new })
                    end
                    assert_equal e.message,
                                 "manifest /path/to/manifest.xml "\
                                 "of 1 from main configuration lists 'does_not_exist' "\
                                 "as dependency, but it is neither a normal package nor "\
                                 "an osdeps package. osdeps reports: cannot resolve "\
                                 "does_not_exist: does_not_exist is not an osdep "\
                                 "and it cannot be resolved as a source package"
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
        end
    end
end

