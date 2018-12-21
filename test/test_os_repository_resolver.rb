require 'autoproj/test'

# Tests for OSRepositoryResolver
module Autoproj
    describe OSRepositoryResolver do
        attr_reader :subject
        attr_reader :definitions

        before do
            @subject = OSRepositoryResolver.new
            @definitions = [{ 'ubuntu' => [{ 'xenial' => nil, 'type' => 'repo' }] }]
        end

        describe '#load' do
            it 'raises if file does not exist' do
                assert_raises do
                    OSRepositoryResolver.load('/does/not/exist')
                end
            end
            it 'raises if file has invalid yml syntax' do
                assert_raises do
                    OSRepositoryResolver.load(File.join(File.dirname(__FILE__), 'data', 'invalid.osrepos'))
                end
            end
            it 'verifies and loads definitions if yml syntax is correct' do
                @subject = flexmock(OSRepositoryResolver)

                subject.should_receive(:verify_definitions).with(definitions)
                result = subject.load(File.join(File.dirname(__FILE__), 'data', 'test.osrepos'))
                assert_equal definitions, result.definitions
            end
        end
        describe '#merge' do
            it 'merges definitions in the receiver' do
                new_defs = [{ 'debian' => [{ 'jessie' => nil, 'type' => 'key' }] }]
                new_resolver = OSRepositoryResolver.new(new_defs, '/path/to/some.osrepos')

                @subject = OSRepositoryResolver.new(definitions, '/foo/test.osrepos')
                @subject.merge(new_resolver)

                all_definitions = []
                all_definitions << [['/foo/test.osrepos'], definitions.first]
                all_definitions << [['/path/to/some.osrepos'], new_defs.first]

                assert_equal subject.all_definitions, all_definitions.to_set
            end
        end
        describe '#definitions' do
            it 'returns an array of the merged definitions' do
                definitions << { 'debian' => [{ 'jessie' => nil, 'type' => 'key' }] }
                definitions << { 'debian' => [{ 'jessie' => nil, 'type' => 'key' }] }
                @subject = OSRepositoryResolver.new(definitions, '/foo/test.osrepos')

                assert_equal subject.definitions, definitions.uniq
            end
        end
        describe '#all_entries' do
            it 'returns an array of the merged entries' do
                definitions << { 'debian' => [{ 'jessie' => nil, 'type' => 'key' }] }
                definitions << { 'debian' => [{ 'jessie' => nil, 'type' => 'key' }] }
                @subject = OSRepositoryResolver.new(definitions, '/foo/test.osrepos')

                assert_equal subject.all_entries, [{ 'type' => 'repo' }, { 'type' => 'key' }]
            end
        end
        describe '#resolved_entries' do
            it 'returns an array of the entries valid for this OS' do
                definitions << { 'debian' => [{ 'jessie' => nil, 'type' => 'key' }] }
                definitions << { 'debian' => [{ 'jessie' => nil, 'type' => 'key' }] }

                @subject = OSRepositoryResolver.new(
                    definitions,
                    '/foo/test.osrepos',
                    operating_system: [['ubuntu'], ['xenial']]
                )

                assert_equal subject.resolved_entries, [{ 'type' => 'repo' }]
            end
        end
        describe '#resolved_entries' do
            it 'allows "default" as a release name while resolving entries' do
                definitions << { 'ubuntu' => [{ 'default' => nil, 'type' => 'key' }] }
                definitions << { 'debian' => [{ 'jessie' => nil, 'type' => 'foo' }] }

                @subject = OSRepositoryResolver.new(
                    definitions,
                    '/foo/test.osrepos',
                    operating_system: [['ubuntu'], ['xenial']]
                )

                assert_equal subject.resolved_entries, [{ 'type' => 'repo' }, { 'type' => 'key' }]
            end
        end
        describe '#verify_definitions' do
            it 'throws if definitions are not an array' do
                assert_raises ArgumentError do
                    OSRepositoryResolver.verify_definitions('type' => 'repo')
                end
            end
            it 'throws if OS element is not a hash' do
                assert_raises ArgumentError do
                    OSRepositoryResolver.verify_definitions(['ubuntu'])
                end
            end
            it 'throws if release element is not a array' do
                assert_raises ArgumentError do
                    OSRepositoryResolver.verify_definitions([{ 'ubuntu' => 'xenial' }])
                end
            end
            it 'throws if first element of the release hash is not nil' do
                assert_raises ArgumentError do
                    OSRepositoryResolver.verify_definitions([{ 'ubuntu' => [{ 'type' => 'repo' }] }])
                end
            end
            it 'does not throw if definitions are valid' do
                OSRepositoryResolver.verify_definitions([{ 'ubuntu' => [{ 'xenial' => nil, 'type' => 'repo' }] }])
            end
        end
    end
end
