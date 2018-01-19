require 'autoproj/test'
$autoproj_disable_github_gitorious_definitions = true
require 'autoproj/git_server_configuration'

module Autoproj
    describe 'git_server_configuration' do
        before do
            @config = Autoproj::Configuration.new
        end

        def self.url_resolution_behavior(c, lazy: nil)
            before do
                @config.set('MYGIT', 'http,git,ssh', true)
                Autoproj.git_server_configuration(
                    'MYGIT', 'mygit',
                    git_url: 'mygit-git-url',
                    ssh_url: 'mygit-ssh-url',
                    http_url: 'mygit-http-url',
                    config: @config,
                    lazy: lazy)
                @expected = Hash[
                    type: 'git',
                    push_to: 'mygit-git-url/repo.git',
                    retry_count: 10,
                    repository_id: "mygit:/repo.git"]
            end

            it "expands shortcuts into their parts" do
                @config.set('MYGIT', 'git', true)
                Autoproj.git_server_configuration('MYGIT', 'mygit', config: @config, lazy: lazy)
                Autoproj.call_source_handler('mygit', 'repo', Hash.new)
                assert_equal "git://mygit", @config.get("MYGIT_ROOT")
                assert_equal "git@mygit:", @config.get("MYGIT_PUSH_ROOT")
                assert_equal "git@mygit:", @config.get("MYGIT_PRIVATE_ROOT")
            end

            it "validates that the entries returned by the user are known" do
                @config.reset('MYGIT')
                flexmock(STDOUT).should_receive(:print, :puts)
                flexmock(STDIN).should_receive(:readline).once.and_return('http,ssh,unknown')
                flexmock(STDIN).should_receive(:readline).once.and_return('http,git,ssh')
                Autoproj.git_server_configuration('MYGIT', 'mygit', config: @config, lazy: lazy)
                Autoproj.call_source_handler('mygit', 'repo', Hash.new)
                assert_equal "https://git.mygit", @config.get("MYGIT_ROOT")
                assert_equal "git://mygit", @config.get("MYGIT_PUSH_ROOT")
                assert_equal "git@mygit:", @config.get("MYGIT_PRIVATE_ROOT")
            end

            it "validates that the entries stored in configuration are known" do
                flexmock(Autoproj).should_receive(:warn).with("unknown is not a known access method")
                @config.set('MYGIT', 'http,git,unknown', true)
                flexmock(@config).should_receive(:reset).once.and_return { @config.set('MYGIT', 'http,git,ssh', true) }
                Autoproj.git_server_configuration('MYGIT', 'mygit', config: @config, lazy: lazy)
                Autoproj.call_source_handler('mygit', 'repo', Hash.new)
                assert_equal "https://git.mygit", @config.get("MYGIT_ROOT")
                assert_equal "git://mygit", @config.get("MYGIT_PUSH_ROOT")
                assert_equal "git@mygit:", @config.get("MYGIT_PRIVATE_ROOT")
            end

            it "refuses disabled entries" do
                flexmock(Autoproj).should_receive(:warn).with("ssh is disabled on mygit")
                @config.set('MYGIT', 'http,git,ssh', true)
                flexmock(@config).should_receive(:reset).once.and_return { @config.set('MYGIT', 'http,git,git', true) }
                Autoproj.git_server_configuration('MYGIT', 'mygit', config: @config, lazy: lazy, disabled_methods: ['ssh'])
                Autoproj.call_source_handler('mygit', 'repo', Hash.new)
                assert_equal "https://git.mygit", @config.get("MYGIT_ROOT")
                assert_equal "git://mygit", @config.get("MYGIT_PUSH_ROOT")
                assert_equal "git://mygit", @config.get("MYGIT_PRIVATE_ROOT")
            end

            it "uses the pull method by default for private if the private access method is not explicitely given" do
                @config.set('MYGIT', 'http,git', true)
                Autoproj.git_server_configuration('MYGIT', 'mygit', config: @config, lazy: lazy)
                Autoproj.call_source_handler('mygit', 'repo', Hash.new)
                assert_equal "https://git.mygit", @config.get("MYGIT_ROOT")
                assert_equal "git://mygit", @config.get("MYGIT_PUSH_ROOT")
                assert_equal "git://mygit", @config.get("MYGIT_PRIVATE_ROOT")
            end

            it "does not add an extra .git at the end of the url if there is one already" do
                expected = @expected.merge(url: 'mygit-http-url/repo.git', interactive: false)
                assert_equal expected,
                    Autoproj.call_source_handler('mygit', 'repo.git', Hash.new)
            end

            it "handles urls that start with a leading slash" do
                expected = @expected.merge(url: 'mygit-http-url/repo.git', interactive: false)
                assert_equal expected,
                    Autoproj.call_source_handler('mygit', '/repo.git', Hash.new)
            end

            it "adds a .git at the end of the repository if it does not have one" do
                expected = @expected.merge(url: 'mygit-http-url/repo.git', interactive: false)
                assert_equal expected,
                    Autoproj.call_source_handler('mygit', 'repo', Hash.new)
            end

            it "resolves public URLs according to the first two entries of the configuration" do
                expected = @expected.merge(url: 'mygit-http-url/repo.git', interactive: false)
                assert_equal expected,
                    Autoproj.call_source_handler('mygit', 'repo', Hash.new)
            end

            it "resolves private URLs according to the last and second entries of the configuration" do
                expected = @expected.merge(url: 'mygit-ssh-url/repo.git', interactive: false)
                assert_equal expected,
                    Autoproj.call_source_handler('mygit', 'repo', private: true)
            end

            it "sets interactive to false if the private access URL is ssh" do
                @config.set('MYGIT', 'http,git,ssh', true)
                Autoproj.git_server_configuration('MYGIT', 'mygit', config: @config, lazy: lazy)
                refute Autoproj.call_source_handler('mygit', 'repo', private: true).fetch(:interactive)
            end

            it "sets interactive to true if the private access URL is http" do
                @config.set('MYGIT', 'http,git,http', true)
                Autoproj.git_server_configuration('MYGIT', 'mygit', config: @config, lazy: lazy)
                assert Autoproj.call_source_handler('mygit', 'repo', private: true).fetch(:interactive)
            end
        end

        describe "lazy: false" do
            it "resolves the configuration within the definition call" do
                flexmock(@config).should_receive(:get).with('MYGIT').once.and_return('http,git,ssh')
                Autoproj.git_server_configuration('MYGIT', 'mygit', config: @config)
            end

            describe "URL resolution" do
                url_resolution_behavior(self, lazy: false)
            end
        end

        describe "lazy: true" do
            it "resolves the configuration after the definition call" do
                flexmock(@config).should_receive(:get).with('MYGIT').never
                Autoproj.git_server_configuration('MYGIT', 'mygit', config: @config, lazy: true)
            end

            describe "URL resolution" do
                url_resolution_behavior(self, lazy: true)
            end
        end
    end
end

