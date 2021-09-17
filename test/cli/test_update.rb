require "autoproj/test"
require "autoproj/cli/main"
require "autoproj/cli/update"

module Autoproj
    module CLI
        describe Update do
            attr_reader :cli

            before do
                ws_create
                @cli = Update.new(ws)
            end

            describe "the main CLI" do
                describe "-n" do
                    it "turns dependencies off" do
                        flexmock(Update).new_instances
                                        .should_receive(:run).with([], hsh(deps: false)).once
                        in_ws do
                            Main.start(["update", "-n", "--silent"])
                        end
                    end
                end
            end

            describe "#validate_options" do
                it "normalizes the selection" do
                    flexmock(cli).should_receive(:normalize_command_line_package_selection)
                                 .with(selection = flexmock(empty?: false))
                                 .and_return([normalized_selection = flexmock(empty?: false),
                                              false])

                    selection, _options = cli.validate_options(selection, Hash.new)
                    assert_equal normalized_selection, selection
                end

                describe "the aup mode" do
                    it "sets the selection to the current directory" do
                        selection, = cli.validate_options([], aup: true)
                        assert_equal ["#{Dir.pwd}/"], selection
                    end
                    it "leaves an explicit selection alone" do
                        selection, = cli.validate_options(["/a/path"], aup: true)
                        assert_equal ["/a/path"], selection
                    end
                    it "leaves an empty selection alone if --config is given" do
                        selection, = cli.validate_options([], aup: true, config: true)
                        assert_equal [], selection
                    end
                    it "leaves an empty selection alone if --all is given" do
                        selection, = cli.validate_options([], aup: true, all: true)
                        assert_equal [], selection
                    end
                    it "sets the 'all' flag automatically if given no explicit arguments and the working directory is the workspace's root" do
                        Dir.chdir(ws.root_dir) do
                            _args, options = cli.validate_options([], aup: true)
                            assert options[:all]
                        end
                    end
                    it "does not set the 'all' flag automatically if given explicit arguments even if the working directory is the workspace's root" do
                        Dir.chdir(ws.root_dir) do
                            _args, options = cli.validate_options(["arg"], aup: true)
                            refute options[:all]
                        end
                    end
                end

                it "normalizes --force-reset into reset: :force" do
                    _, options = cli.validate_options([], force_reset: true)
                    assert !options.has_key?(:force_reset)
                    assert_equal :force, options[:reset]
                end

                describe "the mainline option" do
                    it "leaves it to false by default" do
                        _, options = cli.validate_options([], Hash.new)
                        assert !options[:mainline]
                    end

                    it "normalizes --mainline" do
                        _, options = cli.validate_options([], mainline: "mainline")
                        assert_equal true, options[:mainline]
                    end

                    it "normalizes --mainline=true" do
                        _, options = cli.validate_options([], mainline: "true")
                        assert_equal true, options[:mainline]
                    end

                    it "leaves an explicit --mainline=package_set_name" do
                        _, options = cli.validate_options([], mainline: "package_set_name")
                        assert_equal "package_set_name", options[:mainline]
                    end
                end

                describe "what is going to be updated" do
                    it "updates everything if is selected on the command line" do
                        _, options = cli.validate_options([], Hash.new)
                        assert_equal [true, true, true], options.values_at(:autoproj, :config, :packages)
                    end

                    it "does not attempt to update autoproj if --checkout-only is given" do
                        _, options = cli.validate_options([], checkout_only: true)
                        assert_equal [false, true, true], options.values_at(:autoproj, :config, :packages)
                    end

                    it "only updates autoproj if nothing has been selected explicitely and --autoproj was given" do
                        _, options = cli.validate_options([], autoproj: true)
                        assert_equal [true, false, false], options.values_at(:autoproj, :config, :packages)
                    end

                    it "updates autoproj and packages if nothing has been selected explicitely and both --autoproj and --all were given" do
                        _, options = cli.validate_options([], autoproj: true, all: true)
                        assert_equal [true, false, true], options.values_at(:autoproj, :config, :packages)
                    end

                    it "only updates the configuration if nothing has been selected explicitely and --config was given" do
                        _, options = cli.validate_options([], config: true)
                        assert_equal [false, true, false], options.values_at(:autoproj, :config, :packages)
                    end

                    it "updates config and packages if nothing has been selected explicitely and both --config and --all were given" do
                        _, options = cli.validate_options([], config: true, all: true)
                        assert_equal [false, true, true], options.values_at(:autoproj, :config, :packages)
                    end

                    it "updates autoproj and the configuration if nothing has been selected explicitely and both --autoproj and --config were given" do
                        _, options = cli.validate_options([], autoproj: true, config: true)
                        assert_equal [true, true, false], options.values_at(:autoproj, :config, :packages)
                    end

                    it "updates autoproj, the configuration and the packages if nothing has been selected explicitely and --autoproj, --config and --all were given" do
                        _, options = cli.validate_options([], autoproj: true, config: true, all: true)
                        assert_equal [true, true, true], options.values_at(:autoproj, :config, :packages)
                    end

                    it "only updates the configuration if its path is selected an nothing else was selected explicitely" do
                        _, options = cli.validate_options([ws.config_dir], Hash.new)
                        assert_equal [false, true, false], options.values_at(:autoproj, :config, :packages)
                    end

                    it "updates autoproj and the configuration if the configuration path is selected and --autoproj was given" do
                        _, options = cli.validate_options([ws.config_dir], autoproj: true)
                        assert_equal [true, true, false], options.values_at(:autoproj, :config, :packages)
                    end

                    it "updates configuration and packages if a configuration path and a non-configuration path is selected" do
                        _, options = cli.validate_options([ws.config_dir, "/a/path"], Hash.new)
                        assert_equal [false, true, true], options.values_at(:autoproj, :config, :packages)
                    end

                    it "only updates packages if a non-configuration path is selected an nothing else was selected explicitely" do
                        _, options = cli.validate_options(["/a/path"], Hash.new)
                        assert_equal [false, false, true], options.values_at(:autoproj, :config, :packages)
                    end

                    it "updates configuration and packages if a non-configuration path is selected and --config was given" do
                        _, options = cli.validate_options(["/a/path"], config: true)
                        assert_equal [false, true, true], options.values_at(:autoproj, :config, :packages)
                    end

                    it "updates autoproj and packages if a non-configuration path is selected and --config was given" do
                        _, options = cli.validate_options(["/a/path"], autoproj: true)
                        assert_equal [true, false, true], options.values_at(:autoproj, :config, :packages)
                    end

                    it "updates autoproj, configuration and packages if a non-configuration path is selected and both --autoproj and --config were given" do
                        _, options = cli.validate_options(["/a/path"], autoproj: true, config: true)
                        assert_equal [true, true, true], options.values_at(:autoproj, :config, :packages)
                    end

                    it "updates autoproj, the configuration and the packages if both configuration and package paths were selected and --autoproj was given" do
                        _, options = cli.validate_options([ws.config_dir, "/a/path"], autoproj: true)
                        assert_equal [true, true, true], options.values_at(:autoproj, :config, :packages)
                    end
                end
            end

            describe "#run" do
                it "updates autoproj if autoproj: true" do
                    flexmock(ws).should_receive(:update_autoproj).once
                    cli.run([], autoproj: true)
                end
                it "does not autoproj if autoproj: false" do
                    flexmock(ws).should_receive(:update_autoproj).never
                    cli.run([], autoproj: false)
                end

                it "updates the configuration in checkout_only mode with config: false" do
                    flexmock(ws).should_receive(:load_package_sets)
                                .with(hsh(checkout_only: true)).once
                    cli.run([], config: false)
                end
                it "updates the configuration in checkout_only mode if checkout_only is set" do
                    flexmock(ws).should_receive(:load_package_sets)
                                .with(hsh(checkout_only: true)).once
                    cli.run([], checkout_only: true)
                end
                it "properly sets up packages while updating configuration only" do
                    flexmock(ws).should_receive(:setup_all_package_directories)
                                .ordered.once
                    flexmock(ws).should_receive(:finalize_package_setup)
                                .ordered.once
                    cli.run([], config: true)
                end
                it "passes options to the osdep installer for package import" do
                    flexmock(Ops::Import).new_instances
                                         .should_receive(:import_packages)
                                         .with(PackageSelection, hsh(checkout_only: true, install_vcs_packages: Hash[install_only: true]))
                                         .once
                                         .and_return([[], []])
                    cli.run([], packages: true, checkout_only: true, osdeps: true)
                end
                it "raises CLIInvalidSelection if an excluded package is in the dependency tree" do
                    pkg0 = ws_add_package_to_layout :cmake, "pkg0"
                    pkg1 = ws_define_package :cmake, "pkg1"
                    pkg0.depends_on pkg1
                    selection = PackageSelection.new
                    selection.select("pkg0", "pkg0")
                    @ws.manifest.exclude_package "pkg1", "test"
                    assert_raises(CLIInvalidSelection) do
                        cli.run(["pkg0"], packages: true, checkout_only: true, osdeps: true)
                    end
                end

                it "does not set the reporting path if the report argument is false" do
                    flexmock(Ops::Import).should_receive(:new)
                                         .with(any, report_path: nil)
                                         .once.pass_thru
                    cli.run([], report: false)
                end

                describe "keep_going: false" do
                    it "passes exceptions from package set updates" do
                        import_failure = Class.new(ImportFailed)
                        flexmock(ws).should_receive(:load_package_sets)
                                    .and_raise(import_failure.new([]))
                        flexmock(cli).should_receive(:update_packages).never
                        assert_raises(import_failure) do
                            cli.run([], keep_going: false, packages: true)
                        end
                    end

                    it "passes exceptions from package updates" do
                        import_failure = Class.new(PackageImportFailed)
                        flexmock(Ops::Import).new_instances.should_receive(:import_packages)
                                             .and_raise(import_failure.new([]))
                        assert_raises(import_failure) do
                            cli.run([], keep_going: false, packages: true)
                        end
                    end
                end

                describe "keep_going: true" do
                    attr_reader :pkg_set_failure, :pkg_failure

                    before do
                        @pkg_set_failure = Class.new(ImportFailed)
                        @pkg_failure = Class.new(PackageImportFailed)
                    end
                    def mock_package_set_failure(*errors)
                        flexmock(ws).should_receive(:load_package_sets)
                                    .once.and_raise(pkg_set_failure.new(errors))
                    end

                    def mock_package_failure(*errors, **options)
                        flexmock(Ops::Import).new_instances.should_receive(:import_packages)
                                             .once.and_raise(pkg_failure.new(errors, **options))
                    end

                    it "passes exceptions from package set updates if no packages would be updated" do
                        mock_package_set_failure
                        assert_raises(pkg_set_failure) do
                            cli.run([], keep_going: true, packages: false)
                        end
                    end

                    it "does attempt package updates even if the package set update failed" do
                        mock_package_set_failure
                        flexmock(Ops::Import).new_instances.should_receive(:import_packages)
                                             .once.and_return([], [])
                        assert_raises(pkg_set_failure) do
                            cli.run([], keep_going: true, packages: true)
                        end
                    end

                    it "raises the package set update failure if the package update did not fail" do
                        mock_package_set_failure
                        flexmock(Ops::Import).new_instances.should_receive(:import_packages)
                                             .and_return([], [])
                        assert_raises(pkg_set_failure) do
                            cli.run([], keep_going: true, packages: true)
                        end
                    end

                    it "raises the package update failure if the package set update did not fail" do
                        mock_package_failure
                        assert_raises(pkg_failure) do
                            cli.run([], keep_going: true, packages: true)
                        end
                    end

                    it "concatenates package and package set import failures" do
                        mock_package_set_failure(original_pkg_set_failure = flexmock)
                        mock_package_failure(original_pkg_failure = flexmock)
                        failure = assert_raises(ImportFailed) do
                            cli.run([], keep_going: true, packages: true)
                        end
                        assert_equal [original_pkg_set_failure, original_pkg_failure],
                                     failure.original_errors
                    end

                    it "performs osdep import based on the return value of #import_packages if the package set import failed but not the package update" do
                        mock_package_set_failure
                        flexmock(Ops::Import).new_instances.should_receive(:import_packages)
                                             .and_return([[], ["test"]])
                        flexmock(ws).should_receive(:install_os_packages).once
                                    .with(["test"], Hash)
                        assert_raises(pkg_set_failure) do
                            cli.run([], keep_going: true, packages: true, osdeps: true)
                        end
                    end

                    it "performs osdep import based on the value encoded in the import failure exception if the package import failed" do
                        mock_package_failure(osdep_packages: ["test"])
                        flexmock(ws).should_receive(:install_os_packages).once
                                    .with(["test"], Hash)
                        assert_raises(pkg_failure) do
                            cli.run([], keep_going: true, packages: true, osdeps: true)
                        end
                    end
                end
            end
        end
    end
end
