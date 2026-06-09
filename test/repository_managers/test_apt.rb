require "autoproj/test"

module Autoproj
    # Tests for APT repository manager
    module RepositoryManagers
        describe APT do
            attr_reader :sources_dir
            attr_reader :sources_file
            attr_reader :autoproj_sources
            attr_reader :subject
            attr_reader :ws

            before do
                @ws = ws_create
                @sources_dir = ws.root_dir
                @autoproj_sources = File.join(sources_dir, "autoproj.list")
                @sources_file = File.join(
                    File.dirname(__FILE__), "sources.list.d", "sources.list"
                )

                FileUtils.cp(sources_file, autoproj_sources)
                @subject = Autoproj::RepositoryManagers::APT.new(
                    ws,
                    sources_dir: sources_dir,
                    autoproj_sources: autoproj_sources,
                    root_needed: false
                )
            end

            it "loads existing entries" do
                assert_equal subject.source_files, [File.join(sources_dir, "autoproj.list")]
                assert_equal fixture_source_list_entries, subject.source_entries
            end

            describe "#parse_source_line" do
                it "throws if line is invalid" do
                    assert_raises ConfigError do
                        subject.parse_source_line("invalid line")
                    end
                end
            end

            describe "#add_source" do
                it "enables an entry if it already exists" do
                    line = "deb http://archive.canonical.com/ubuntu xenial partner"
                    assert subject.add_source(line, autoproj_sources)

                    entries = fixture_source_list_entries
                    entries[autoproj_sources][1][:enabled] = true
                    assert_equal entries, subject.source_entries
                end

                it "append line to file if entry does not exist" do
                    line = "deb http://packages.ros.org/ros/ubuntu xenial main"
                    assert subject.add_source(line, autoproj_sources)

                    entries = fixture_source_list_entries
                    entries[autoproj_sources] << {
                        valid: true,
                        enabled: true,
                        source: "deb http://packages.ros.org/ros/ubuntu xenial main",
                        source_id: "deb http://packages.ros.org/ros/ubuntu xenial main"
                    }
                    assert_equal entries, subject.source_entries
                end

                it "does nothing if entry exists and is enabled" do
                    line = "deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted"
                    refute subject.add_source(line, autoproj_sources)
                    assert_equal fixture_source_list_entries, subject.source_entries
                end

                it "detects a new signed-by key" do
                    line = "deb [signed-by=/some/path] http://br.archive.ubuntu.com/ubuntu/ xenial main restricted"
                    assert subject.add_source(line, autoproj_sources)

                    entries = fixture_source_list_entries
                    entries[autoproj_sources][0] = {
                        valid: true,
                        enabled: true,
                        signed_by: "/some/path",
                        source: "deb [signed-by=/some/path] http://br.archive.ubuntu.com/ubuntu/ xenial main restricted",
                        source_id: "deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted"
                    }
                    assert_equal entries, subject.source_entries
                end

                it "allows adding a new signed-by path by argument" do
                    line = "deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted"
                    assert subject.add_source(line, autoproj_sources, signed_by: "/some/path")

                    entries = fixture_source_list_entries
                    entries[autoproj_sources][0] = {
                        valid: true,
                        enabled: true,
                        signed_by: "/some/path",
                        source: "deb [signed-by=/some/path] http://br.archive.ubuntu.com/ubuntu/ xenial main restricted",
                        source_id: "deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted"
                    }
                    assert_equal entries, subject.source_entries
                end

                it "allows changing a signed-by path by argument" do
                    line = "deb [signed-by=/some/path] http://br.archive.ubuntu.com/ubuntu/ xenial main restricted"
                    assert subject.add_source(line, autoproj_sources)

                    line = "deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted"
                    assert subject.add_source(line, autoproj_sources, signed_by: "/some/other/path")

                    entries = fixture_source_list_entries
                    entries[autoproj_sources][0] = {
                        valid: true,
                        enabled: true,
                        signed_by: "/some/other/path",
                        source: "deb [signed-by=/some/other/path] http://br.archive.ubuntu.com/ubuntu/ xenial main restricted",
                        source_id: "deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted"
                    }
                    assert_equal entries, subject.source_entries
                end
            end
            describe "#install" do
                it "does nothing if definitions are already installed" do
                    repo = "deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted"
                    definitions = [
                        {
                            "type" => "repo",
                            "repo" => repo
                        },
                        {
                            "type" => "key",
                            "id" => "ABC",
                            "keyserver" => "hkp://foo"
                        }
                    ]
                    @subject = flexmock(subject)

                    subject
                        .should_receive(:find_matching_entry_from_repo)
                        .with(repo)
                        .and_return([sources_file, enabled: true])

                    subject
                        .should_receive(:anonymous_key_exist?)
                        .with("ABC")
                        .and_return(true)

                    subject.should_receive(:add_anonymous_key_from_keyserver).never
                    subject.should_receive(:apt_update).never
                    subject.install(definitions)
                end
                it "installs the provided definitions" do
                    repo = "deb http://packages.ros.org/ros/ubuntu xenial main"
                    definitions = [
                        {
                            "type" => "repo",
                            "repo" => repo
                        },
                        {
                            "type" => "key",
                            "id" => "ABC",
                            "keyserver" => "hkp://foo"
                        },
                        {
                            "type" => "key",
                            "id" => "DEF",
                            "url" => "http://foo/bar.key"
                        }
                    ]
                    @subject = flexmock(subject)

                    subject.should_receive(:add_anonymous_key_from_keyserver).with(
                        "ABC",
                        "hkp://foo"
                    ).once.ordered
                    subject.should_receive(:add_anonymous_key_from_url).with(
                        "http://foo/bar.key"
                    ).once.ordered

                    subject.should_receive(:apt_update).once.ordered
                    subject.install(definitions)

                    expected = <<~CONTENT
                        deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted
                        # deb http://archive.canonical.com/ubuntu xenial partner
                        deb http://packages.ros.org/ros/ubuntu xenial main
                    CONTENT
                    assert_equal expected.strip, File.read(autoproj_sources).strip
                end
                it "uses the new key management scheme for named keys" do
                    repo = "deb http://packages.ros.org/ros/ubuntu xenial main"
                    repo2 = "deb http://packages.ros.org/ros/ubuntu2 xenial main"
                    definitions = [
                        {
                            "type" => "repo",
                            "repo" => repo,
                            "key" => "test"
                        },
                        {
                            "type" => "key",
                            "name" => "test",
                            "id" => "ABC",
                            "keyserver" => "hkp://foo"
                        },
                        {
                            "type" => "repo",
                            "repo" => repo2,
                            "key" => "test2"
                        },
                        {
                            "type" => "key",
                            "name" => "test2",
                            "id" => "DEF",
                            "url" => "https://somewhere/somefile.key"
                        }
                    ]
                    @subject = flexmock(subject)

                    subject.should_receive(:add_named_key_from_keyserver).with(
                        "#{sources_dir}/keyrings/autoproj_test_ABC.gpg",
                        "ABC",
                        "hkp://foo"
                    ).once.ordered
                    subject.should_receive(:add_named_key_from_url).with(
                        "#{sources_dir}/keyrings/autoproj_test2_DEF.asc",
                        "https://somewhere/somefile.key"
                    ).once.ordered

                    subject.should_receive(:apt_update).once.ordered
                    subject.install(definitions)

                    expected = <<~CONTENT
                        deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted
                        # deb http://archive.canonical.com/ubuntu xenial partner
                        deb [signed-by=#{sources_dir}/keyrings/autoproj_test_ABC.gpg] http://packages.ros.org/ros/ubuntu xenial main
                        deb [signed-by=#{sources_dir}/keyrings/autoproj_test2_DEF.asc] http://packages.ros.org/ros/ubuntu2 xenial main
                    CONTENT
                    assert_equal expected.strip, File.read(autoproj_sources).strip
                end
            end

            def fixture_source_list_entries
                {
                    autoproj_sources => [
                        {
                            valid: true,
                            enabled: true,
                            source: "deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted",
                            source_id: "deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted"
                        },
                        {
                            valid: true,
                            enabled: false,
                            source: "deb http://archive.canonical.com/ubuntu xenial partner",
                            source_id: "deb http://archive.canonical.com/ubuntu xenial partner"
                        }
                    ]
                }
            end
        end
    end
end
