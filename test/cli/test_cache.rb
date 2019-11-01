require 'autoproj/test'
require 'autoproj/cli/cache'

module Autoproj
    module CLI
        describe Cache do
            describe '#validate_options' do
                before do
                    @ws = ws_create
                    @cli = Cache.new(@ws)
                end

                after do
                    Autobuild::Importer.default_cache_dirs = nil
                end

                it 'uses the default cache dir if no arguments are given' do
                    Autobuild::Importer.default_cache_dirs = '/some/path'
                    *argv, _options = @cli.validate_options([], {})
                    assert_equal ['/some/path'], argv
                end

                it 'raises if no arguments are given and there is no default' do
                    Autobuild::Importer.default_cache_dirs = nil
                    assert_raises(CLIInvalidArguments) do
                        @cli.validate_options([], {})
                    end
                end

                it 'passes through plain packages names in gems_compile' do
                    _, options = @cli.validate_options(
                        ['/cache/path'], gems_compile: ['some_gem']
                    )
                    assert_equal [['some_gem', artifacts: []]],
                                 options[:gems_compile]
                end

                it 'interprets the + signs in the gems_compile option' do
                    _, options = @cli.validate_options(
                        ['/cache/path'], gems_compile: ['some_gem+artifact/path']
                    )
                    assert_equal [['some_gem', artifacts: ['artifact/path']]],
                                 options[:gems_compile]
                end
            end
        end
    end
end
