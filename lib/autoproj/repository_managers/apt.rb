# frozen_string_literal: false

require 'open3'
require 'pathname'
require 'open-uri'

module Autoproj
    module RepositoryManagers
        # Apt repository manager class
        class APT < Manager
            attr_reader :source_files
            attr_reader :source_entries

            SOURCES_DIR = '/etc/apt'.freeze
            SOURCE_TYPES = ['deb', 'deb-src'].freeze
            AUTOPROJ_SOURCES = '/etc/apt/sources.list.d/autoproj.list'.freeze

            def initialize(ws)
                @source_files = Dir[File.join(SOURCES_DIR, '**', '*.list')]
                @source_entries = {}

                source_files.each { |file| load_sources_from_file(file) }
                super(ws)
            end

            def os_dependencies
                super + ['archive-keyring', 'gnupg', 'apt-transport-https']
            end

            def load_sources_from_file(file)
                contents = File.open(file).read
                contents.gsub!(/\r\n?/, "\n")

                contents.each_line do |line|
                    @source_entries[file] ||= []
                    @source_entries[file] << parse_source_line(line, raise_if_invalid: false)
                end
            end

            def parse_source_line(line, raise_if_invalid: true)
                entry = {}
                entry[:valid] = false
                entry[:enabled] = true
                entry[:source] = ''
                entry[:comment] = ''

                line.strip!
                if line.start_with?('#')
                    entry[:enabled] = false
                    line = line[1..-1]
                end

                i = line.index('#')
                if i&.positive?
                    entry[:comment] = line[(i + 1)..-1].strip
                    line = line[0..(i - 1)]
                end

                entry[:source] = line.strip
                chunks = entry[:source].split
                entry[:valid] = true if SOURCE_TYPES.include?(chunks[0])
                entry[:source] = chunks.join(' ')

                if raise_if_invalid && (!entry[:valid] || !entry[:enabled])
                    raise ConfigError, "Invalid source line: #{entry[:source]}"
                end

                entry
            end

            def add_source(source, file = nil)
                file = if file
                           File.join(SOURCES_DIR, 'sources.list.d', file)
                       else
                           AUTOPROJ_SOURCES
                       end

                new_entry = parse_source_line(source)
                found = entry_exist?(new_entry)

                if found
                    file = found.first
                    entry = found.last
                    return false if entry[:enabled]

                    enable_entry_in_file(file, entry)
                else
                    add_entry_to_file(file, new_entry)
                end
            end

            def append_entry(contents, entry)
                unless entry[:enabled]
                    contents << '#'
                    contents << ' ' unless entry[:source].start_with?('#')
                end

                contents << entry[:source]
                contents << "# #{entry[:comment]}" unless entry[:comment].empty?
                contents << "\n"
            end

            def enable_entry_in_file(file, enable_entry)
                contents = ''
                source_entries[file].each do |entry|
                    entry[:enabled] = true if enable_entry[:source] == entry[:source]
                    append_entry(contents, entry)
                end
                run_tee_command(['sudo', 'tee', file], contents)
                true
            end

            def add_entry_to_file(file, entry)
                run_tee_command(['sudo', 'tee', '-a', file], entry[:source])
                @source_entries[file] ||= []
                @source_entries[file] << entry
                true
            end

            def run_tee_command(command, contents)
                contents = StringIO.new("#{contents}\n")
                Autobuild::Subprocess.run('autoproj', 'osrepos', *command, input_streams: [contents])
            end

            def entry_exist?(new_entry)
                source_entries.each_pair do |file, entries|
                    entry = entries.find { |e| e[:source] == new_entry[:source] }
                    return [file, entry] if entry
                end
                nil
            end

            def source_exist?(source)
                entry_exist?(parse_source_line(source))
            end

            def key_exist?(key)
                exist = false
                Open3.popen3("apt-key export #{key}") do |_, _, stderr, wait_thr|
                    exist = true if wait_thr.value.success? && stderr.read.empty?
                end
                exist
            end

            def apt_update
                Autobuild::Subprocess.run(
                    'autoproj',
                    'osrepos',
                    'sudo',
                    'apt-get',
                    'update'
                )
            end

            def add_apt_key(id, origin, type: :keyserver)
                if type == :keyserver
                    Autobuild::Subprocess.run(
                        'autoproj',
                        'osrepos',
                        'sudo',
                        'apt-key',
                        'adv',
                        '--keyserver',
                        origin,
                        '--recv-key',
                        id,
                    )
                else
                    open(origin) do |io|
                        Autobuild::Subprocess.run(
                            'autoproj',
                            'osrepos',
                            'sudo',
                            'apt-key',
                            'add',
                            '-',
                            input_streams: [io]
                        )
                    end
                end
            rescue Errno::ENOENT, SocketError => e
                raise ConfigError, e.message
            end

            def filter_installed_definitions(definitions)
                definitions = definitions.dup.reject do |definition|
                    if definition['type'] == 'repo'
                        _, entry = source_exist?(definition['repo'])
                        entry && entry[:enabled]
                    else
                        key_exist?(definition['id'])
                    end
                end
                definitions
            end

            def print_installing_definitions(definitions)
                repos = definitions.select { |definition| definition['type'] == 'repo' }
                keys = definitions.select { |definition| definition['type'] == 'key' }

                unless repos.empty?
                    Autoproj.message '  adding apt repositories:'
                    repos.each do |repo|
                        if repo['file']
                            Autoproj.message "    #{repo['repo']}, file: #{repo['file']}"
                        else
                            Autoproj.message "    #{repo['repo']}"
                        end
                    end
                end
                return if keys.empty?

                Autoproj.message '  adding apt keys:'
                keys.each do |key|
                    if key['keyserver']
                        Autoproj.message "    id: #{key['id']}, keyserver: #{key['keyserver']}"
                    else
                        Autoproj.message "    id: #{key['id']}, url: #{key['url']}"
                    end
                end
            end

            # Validates repositories definitions from .osrepos files
            #
            # Examples:
            #
            # - ubuntu:
            #   - xenial:
            #     type: repo
            #     repo: 'deb http://archive.ubuntu.com/ubuntu/ xenial main restricted'
            #
            # - ubuntu:
            #   - xenial:
            #     type: key
            #     id: 630239CC130E1A7FD81A27B140976EAF437D05B5
            #     keyserver: 'hkp://ha.pool.sks-keyservers.net:80'
            #
            # - ubuntu:
            #   - xenial:
            #     type: key
            #     id: D2486D2DD83DB69272AFE98867170598AF249743
            #     url: 'http://packages.osrfoundation.org/gazebo.key'
            #
            def validate_definitions(definitions)
                invalid_string = 'Invalid apt repository definition'
                definitions.each do |definition|
                    raise ConfigError, "#{invalid_string} type: #{definition['type']}" unless %w[repo key].include?(definition['type'])

                    if definition['type'] == 'repo'
                        raise ConfigError, "#{invalid_string}: 'repo' key missing" if definition['repo'].nil?
                        raise ConfigError, "#{invalid_string}: 'repo' should be a String" unless definition['repo'].is_a?(String)
                        raise ConfigError, "#{invalid_string}: 'file' should be a String" if definition['file'] && !definition['file'].is_a?(String)
                        if definition['file'] && Pathname.new(definition['file']).absolute?
                            raise ConfigError, "#{invalid_string}: 'file' should be a relative to #{File.join(SOURCES_DIR, 'sources.list.d')}"
                        end
                    else
                        raise ConfigError, "#{invalid_string}: 'id' key missing" if definition['id'].nil?
                        raise ConfigError, "#{invalid_string}: 'id' should be a String" unless definition['id'].is_a?(String)
                        raise ConfigError, "#{invalid_string}: 'url' conflicts with 'keyserver'" if definition['url'] && definition['keyserver']
                        raise ConfigError, "#{invalid_string}: 'url' should be a String" if definition['url'] && !definition['url'].is_a?(String)
                        raise ConfigError, "#{invalid_string}: 'keyserver' should be a String" if definition['keyserver'] && !definition['keyserver'].is_a?(String)
                    end
                end
            end

            def install(definitions)
                super
                validate_definitions(definitions)
                definitions = filter_installed_definitions(definitions)
                print_installing_definitions(definitions)

                definitions.each do |definition|
                    if definition['type'] == 'repo'
                        add_source(definition['repo'], definition['file'])
                    else
                        type = definition['url'] ? 'url' : 'keyserver'
                        origin = definition[type]
                        add_apt_key(definition['id'], origin, type: type.to_sym)
                    end
                end
                apt_update unless definitions.empty?
            end
        end
    end
end
