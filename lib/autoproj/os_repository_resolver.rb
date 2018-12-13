require 'tempfile'
require 'json'

module Autoproj
    # Manager for OS repository provided by package sets
    class OSRepositoryResolver
        # All the information contained in all the OSrepos files
        attr_reader :all_definitions

        # The operating system
        attr_accessor :operating_system

        def self.load(file)
            raise ArgumentError, "no such file or directory: #{file}" unless File.file?(file)

            error_t = if defined? Psych::SyntaxError
                          [ArgumentError, Psych::SyntaxError]
                      else
                          ArgumentError
                      end

            result = new
            file = File.expand_path(file)
            begin
                data = YAML.safe_load(File.read(file)) || {}
                verify_definitions(data)
            rescue *error_t => e
                raise ConfigError.new, "error in #{file}: #{e.message}", e.backtrace
            end
            result.merge(new(data, file))
            result
        end

        def initialize(defs = [], file = nil, operating_system: nil)
            @operating_system = operating_system
            @all_definitions = Set.new
            if file
                defs.each do |def_|
                    all_definitions << [[file], def_]
                end
            else
                defs.each do |def_|
                    all_definitions << [[], def_]
                end
            end
        end

        def add_entries(entries, file: nil)
            merge(self.class.new(entries, file))
        end

        def merge(info)
            @all_definitions += info.all_definitions
        end

        def definitions
            all_definitions.map(&:last).uniq
        end

        def all_entries
            definitions.map do |distribution|
                distribution.values.map do |release|
                    release.map do |entry|
                        remove_identifier_from_entry(entry.dup)
                    end
                end
            end.flatten
        end

        def remove_identifier_from_entry(entry)
            entry.delete(entry.keys.first)
            entry
        end

        def entry_matches?(entry, identifiers)
            !(entry.keys.first.split(',').map(&:strip) & identifiers).empty?
        end

        def resolved_entries
            os_name, os_version = operating_system
            os_version << 'default' unless os_version.include?('default')

            distribution_filtered = definitions.select do |entry|
                entry_matches?(entry, os_name)
            end.map(&:values).flatten

            release_filtered = distribution_filtered.select { |entry| entry_matches?(entry, os_version) }
            release_filtered.map { |entry| remove_identifier_from_entry(entry.dup) }
        end

        # OS repos definitions must follow the format:
        #
        # - distribution:
        #   - release:
        #     key1: value1
        #     key2: value2
        #
        # The key, value pairs are OS dependent, and will be verified/parsed by the
        # corresponding 'repository manager'. Thus, for a debian-like distribution
        # one would have something like:
        #
        # - ubuntu:
        #   - xenial:
        #     type: repo
        #     repo: 'deb http://br.archive.ubuntu.com/ubuntu/ xenial main restricted'
        def self.verify_definitions(array, path = [])
            verify_type(array, Array, path)
            array.each do |entry|
                verify_type(entry, Hash, path)
                verify_os(entry, (path + [entry]))
            end
        end

        def self.verify_os(hash, path = [])
            verify_type(hash, Hash, path)
            hash.each do |key, value|
                verify_type(key, String, path)
                verify_release(value, (path + [value]))
            end
        end

        def self.verify_release(array, path = [])
            verify_type(array, Array, path)
            array.each do |entry|
                release = entry.first
                verify_type(release[0], String, path)
                verify_type(release[1], NilClass, path)
            end
        end

        def self.verify_type(obj, type, path = [])
            return if obj.is_a?(type)

            raise ArgumentError, "invalid osrepos definition in #{path.join('/')}: "\
                "expected a #{type}, found a #{obj.class}"
        end
    end
end
