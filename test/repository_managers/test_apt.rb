require 'autoproj/test'

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
                @autoproj_sources = File.join(sources_dir, 'autoproj.list')
                @sources_file = File.join(File.dirname(__FILE__), 'sources.list.d', 'sources.list')

                FileUtils.cp(sources_file, sources_dir)
                @subject = Autoproj::RepositoryManagers::APT.new(
                    ws,
                    sources_dir: sources_dir,
                    autoproj_sources: autoproj_sources
                )
            end

            it 'loads existing entries' do
                entries = {
                    File.join(sources_dir, 'sources.list') => [
                        {
                            valid: true,
                            enabled: true,
                            source: 'deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted',
                            comment: ''
                        },
                        {
                            valid: true,
                            enabled: false,
                            source: 'deb http://archive.canonical.com/ubuntu xenial partner',
                            comment: ''
                        }
                    ]
                }

                assert_equal subject.source_files, [File.join(sources_dir, 'sources.list')]
                assert_equal subject.source_entries, entries
            end

            describe '#parse_source_line' do
                it 'throws if line is invalid' do
                    assert_raises ConfigError do
                        subject.parse_source_line('invalid line')
                    end
                end
            end
            describe '#add_source' do
                it 'uncomment line if entry exists' do
                    line = 'deb http://archive.canonical.com/ubuntu xenial partner'
                    updated_file = <<~EOFSOURCE
                        deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted
                        deb http://archive.canonical.com/ubuntu xenial partner\n
                    EOFSOURCE

                    flexmock(Autobuild::Subprocess)
                        .should_receive(:run)
                        .with(
                            'autoproj',
                            'osrepos',
                            'sudo',
                            'tee',
                            File.join(sources_dir, 'sources.list'),
                            on { |opt| opt[:input_streams].first.read == updated_file }
                        )

                    assert subject.add_source(line)
                end
                it 'append line to file if entry does not exist' do
                    line = 'deb http://packages.ros.org/ros/ubuntu xenial main'
                    flexmock(Autobuild::Subprocess)
                        .should_receive(:run)
                        .with(
                            'autoproj',
                            'osrepos',
                            'sudo',
                            'tee',
                            '-a',
                            autoproj_sources,
                            on { |opt| opt[:input_streams].first.read == "#{line}\n" }
                        )

                    assert subject.add_source(line)
                end
                it 'does nothing if entry exists and is enabled' do
                    line = 'deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted'
                    flexmock(Autobuild::Subprocess)
                        .should_receive(:run)
                        .with(any)
                        .never

                    refute subject.add_source(line)
                end
            end
            describe '#install' do
                it 'does nothing if definitions are already installed' do
                    repo = 'deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted'
                    definitions = [
                        {
                            'type' => 'repo',
                            'repo' => repo
                        },
                        {
                            'type' => 'key',
                            'id' => 'ABC',
                            'keyserver' => 'hkp://foo'
                        }
                    ]
                    @subject = flexmock(subject)

                    subject
                        .should_receive(:source_exist?)
                        .with(repo)
                        .and_return([sources_file, enabled: true])

                    subject
                        .should_receive(:key_exist?)
                        .with('ABC')
                        .and_return(true)

                    subject.should_receive(:add_source).with(any, any).never
                    subject.should_receive(:add_apt_key).with(any, any, any).never
                    subject.should_receive(:apt_update).never
                    subject.install(definitions)
                end
                it 'installs the provided definitions' do
                    repo = 'deb http://packages.ros.org/ros/ubuntu xenial main'
                    definitions = [
                        {
                            'type' => 'repo',
                            'repo' => repo
                        },
                        {
                            'type' => 'key',
                            'id' => 'ABC',
                            'keyserver' => 'hkp://foo'
                        },
                        {
                            'type' => 'key',
                            'id' => 'DEF',
                            'url' => 'http://foo/bar.key'
                        }
                    ]
                    @subject = flexmock(subject)

                    subject.should_receive(:add_source).with(repo, nil).once.ordered
                    subject.should_receive(:add_apt_key).with(
                        'ABC',
                        'hkp://foo',
                        type: :keyserver
                    ).once.ordered
                    subject.should_receive(:add_apt_key).with(
                        'DEF',
                        'http://foo/bar.key',
                        type: :url
                    ).once.ordered

                    subject.should_receive(:apt_update).once.ordered
                    subject.install(definitions)
                end
            end
        end
    end
end
