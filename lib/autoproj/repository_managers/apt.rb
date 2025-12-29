# frozen_string_literal: true

require "open3"
require "pathname"
require "open-uri"

module Autoproj
    module RepositoryManagers
        # Apt repository manager class
        class APT < Manager
            attr_reader :source_files
            attr_reader :source_entries
            attr_reader :sources_dir
            attr_reader :autoproj_sources

            SOURCES_DIR = "/etc/apt"
            SOURCE_TYPE_VALIDATION = /^(?:deb|deb-src) /.freeze
            AUTOPROJ_SOURCES = "/etc/apt/sources.list.d/autoproj.list"

            def initialize(
                ws,
                sources_dir: SOURCES_DIR, autoproj_sources: AUTOPROJ_SOURCES,
                root_needed: true
            )
                @sources_dir = sources_dir
                @autoproj_sources = autoproj_sources
                @source_files = Dir[File.join(sources_dir, "**", "*.list")]
                @source_entries = {}
                @root_needed = root_needed

                source_files.each { |file| load_sources_from_file(file) }
                super(ws)
            end

            def os_dependencies
                super + %w[archive-keyring gnupg apt-transport-https]
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
                entry = { valid: false }

                line.strip!
                entry[:enabled] = !line.start_with?("#")

                line = line[1..-1].strip unless entry[:enabled]

                i = line.index("#")
                if i&.positive?
                    entry[:comment] = line[(i + 1)..-1].strip
                    line = line[0..(i - 1)]
                end

                normalized = line.strip.gsub(/\s+/, " ")
                entry[:valid] = SOURCE_TYPE_VALIDATION.match?(normalized)
                if raise_if_invalid && (!entry[:valid] || !entry[:enabled])
                    raise ConfigError, "Invalid source line: #{entry[:source]}"
                end

                entry[:source] = normalized
                if (m = /\[signed-by=(.*)\]/.match(line))
                    entry[:signed_by] = m[1]
                    entry[:source_id] = "#{m.pre_match.strip} #{m.post_match.strip}"
                else
                    entry[:source_id] = entry[:source]
                end

                entry
            end

            KeyID = Struct.new :name, :fingerprint

            def keyid_from_keyfile(path)
                basename = File.basename(path, File.extname(path))
                return unless (m = /autoproj_(\w+)_([A-F0-9]+)/.match(basename))

                KeyID.new(name: m[1], id: m[2])
            end

            def add_source(source, file, signed_by: nil)
                file = File.expand_path(
                    file, File.join(sources_dir, "sources.list.d")
                )

                new_entry = parse_source_line(source)
                entry_update_signed_by(new_entry, signed_by) if signed_by
                old_file, old_entry = find_matching_entry(new_entry)

                unless old_entry
                    add_entry_to_file(file, new_entry)
                    return true
                end

                needs_update = entry_needs_update?(old_entry, new_entry)
                return false unless needs_update

                if old_file == file
                    replace_entry_in_file(file, old_entry, new_entry)
                    return true
                elsif !old_entry[:enabled]
                    # The old entry is disabled, just add
                    add_entry_to_file(file, new_entry)
                    return true
                end

                raise ConfigError,
                      "entry #{old_entry[:source]} already exists in " \
                      "#{old_file}, but is different from what autoproj " \
                      "expects (#{new_entry[:source]}). Update the existing " \
                      "entry manually, or delete it to let autoproj manage it"
            end

            def entry_update_signed_by(entry, signed_by)
                return if entry[:signed_by] == signed_by

                entry[:signed_by] = signed_by
                source = entry[:source]
                type, *rest = source.split(" ")
                rest.shift if rest[0].downcase.start_with?("[signed-by")
                entry[:source] = [type, "[signed-by=#{signed_by}]", *rest].join(" ")
            end

            def replace_entry_in_file(file, old_entry, new_entry)
                entries = source_entries[file]
                idx = entries.index(old_entry)
                entries[idx] = new_entry
            end

            def entry_needs_update?(old, new)
                old[:enabled] != new[:enabled] ||
                    old[:signed_by] != new[:signed_by]
            end

            # @api private
            #
            # Generate the content for the given file based on the entries in
            # source_entries
            def generate_file(file)
                contents = []
                @source_entries[file].each do |entry|
                    generate_file_append_entry(contents, entry)
                end
                contents.join
            end

            # @api private
            #
            # Convert a source entry into a line suitable for a source file
            def generate_file_append_entry(contents, entry)
                contents << "# " unless entry[:enabled]

                contents << entry[:source]
                contents << " # #{entry[:comment]}" if entry[:comment]
                contents << "\n"
            end

            def add_entry_to_file(file, entry)
                @source_entries[file] ||= []
                @source_entries[file] << entry
            end

            def update_source_file(file)
                run_tee_command(file, generate_file(file))
            end

            def run_tee_command(file, contents)
                contents = StringIO.new("#{contents}\n")
                Autobuild::Subprocess.run(
                    "autoproj", "osrepos", *cmd_acquire_root, "tee", file,
                    input_streams: [contents]
                )
            end

            def cmd_acquire_root
                return [] unless @root_needed

                ["sudo"]
            end

            # Find an entry that refers to the same source than the given entry hash
            #
            # Note that the returned entry is not exactly the same. It may have a different
            # signed-by key and/or have an `enabled` flag that is different`
            #
            # @return [(String,Hash),nil] the matching file and entry hash
            def find_matching_entry(new_entry)
                source_entries.each_pair do |file, entries|
                    entry = entries.find { |e| e[:source_id] == new_entry[:source_id] }
                    return [file, entry] if entry
                end

                nil
            end

            def find_matching_entry_from_repo(repo)
                find_matching_entry(parse_source_line(repo))
            end

            def anonymous_key_exist?(key)
                exist = false
                Open3.popen3({ "LANG" => "C" }, "apt-key", "export", key) do |_, _, stderr, wait_thr|
                    success = wait_thr.value.success?
                    stderr = stderr.read
                    has_error = stderr.match(/WARNING: nothing exported/)
                    exist = success && !has_error
                end
                exist
            end

            def apt_update
                Autobuild::Subprocess.run(
                    "autoproj",
                    "osrepos",
                    *cmd_acquire_root,
                    "apt-get",
                    "update"
                )
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
                definitions.each do |definition|
                    case definition["type"]
                    when "repo"
                        validate_repo_definition(definition)
                    when "key"
                        validate_key_definition(definition)
                    else
                        raise ConfigError,
                              "#{INVALID_REPO_MESSAGE} type: #{definition['type']}"
                    end
                end
            end

            INVALID_REPO_MESSAGE = "Invalid apt repository definition"

            # rubocop:disable Style/GuardClause

            def validate_repo_definition(definition)
                if definition["repo"].nil?
                    raise ConfigError, "#{INVALID_REPO_MESSAGE}: 'repo' key missing"
                elsif !definition["repo"].is_a?(String)
                    raise ConfigError,
                          "#{INVALID_REPO_MESSAGE}: 'repo' should be a String"
                elsif definition["file"] && !definition["file"].is_a?(String)
                    raise ConfigError,
                          "#{INVALID_REPO_MESSAGE}: 'file' should be a String"
                elsif definition["file"] && Pathname.new(definition["file"]).absolute?
                    raise ConfigError,
                          "#{INVALID_REPO_MESSAGE}: 'file' should be relative "\
                          "to #{File.join(SOURCES_DIR, 'sources.list.d')}"
                end

                nil
            end

            def validate_key_definition(definition)
                if definition["id"].nil?
                    raise ConfigError, "#{INVALID_REPO_MESSAGE}: 'id' key missing"
                elsif !definition["id"].is_a?(String)
                    raise ConfigError, "#{INVALID_REPO_MESSAGE}: 'id' should be a String"
                elsif definition["url"] && definition["keyserver"]
                    raise ConfigError,
                          "#{INVALID_REPO_MESSAGE}: 'url' conflicts with 'keyserver'"
                elsif definition["url"] && !definition["url"].is_a?(String)
                    raise ConfigError, "#{INVALID_REPO_MESSAGE}: 'url' should be a String"
                elsif definition["keyserver"] && !definition["keyserver"].is_a?(String)
                    raise ConfigError,
                          "#{INVALID_REPO_MESSAGE}: 'keyserver' should be a String"
                end

                nil
            end

            # rubocop:enable Style/GuardClause

            def install(definitions)
                super

                validate_definitions(definitions)

                keys, repos = definitions.partition { _1["type"] == "key" }
                named_keys = keys.to_h { [_1["name"], _1] }

                updated_files = install_repos(repos, named_keys)
                install_keys(keys)
                updated_files.each do |path|
                    update_source_file(path)
                end
                apt_update unless updated_files.empty?
            end

            def install_repos(repos, named_keys)
                repos.each_with_object(Set.new) do |definition, updated_files|
                    repo = definition["repo"]
                    file = definition["file"] || autoproj_sources
                    if (key_name = definition["key"])
                        unless (keydef = named_keys[key_name])
                            raise ConfigError,
                                  "key '#{key_name}' is referenced by entry " \
                                  "#{definition['repo']} from #{file}}, " \
                                  "but this key is not defined"
                        end

                        signed_by = signed_by_path_from_named_key(keydef)
                    end

                    next unless add_source(repo, file, signed_by: signed_by)

                    Autoproj.message "  added or updated apt repository"
                    if definition["file"]
                        Autoproj.message "    #{repo}, file: #{filec}"
                    else
                        Autoproj.message "    #{repo}"
                    end
                    updated_files << file
                end
            end

            def install_keys(keys)
                keys.each do |keydef|
                    if keydef["name"]
                        install_named_key(keydef)
                    else
                        install_anonymous_key(keydef)
                    end
                end
            end

            def signed_by_path_from_named_key(keydef)
                name = keydef.fetch("name")
                id = keydef.fetch("id")
                ext =
                    if keydef["url"]
                        # Assuming ascii-armored file
                        ".asc"
                    else
                        ".gpg"
                    end

                File.join(@sources_dir, "keyrings", "autoproj_#{name}_#{id}#{ext}")
            end

            def install_named_key(keydef)
                path = signed_by_path_from_named_key(keydef)
                return if File.exist?(path)

                Autoproj.message "  adding apt key"

                key_id = keydef.fetch("id")
                if (url = keydef["url"])
                    Autoproj.message "    id: #{key_id}, url: #{url}"
                    add_named_key_from_url(path, url)
                else
                    keyserver = keydef.fetch("keyserver")
                    Autoproj.message "    id: #{key_id}, keyserver: #{keyserver}"
                    add_named_key_from_keyserver(path, key_id, keyserver)
                end
            end

            def install_anonymous_key(definition)
                key_id = definition["id"]
                return if anonymous_key_exist?(key_id)

                Autoproj.message "  adding apt key"

                if (url = definition["url"])
                    Autoproj.message "    id: #{key_id}, url: #{url}"
                    add_anonymous_key_from_url(url)
                else
                    keyserver = definition.fetch("keyserver")
                    Autoproj.message "    id: #{key_id}, keyserver: #{keyserver}"
                    add_anonymous_key_from_keyserver(key_id, keyserver)
                end
            end

            def add_named_key_from_keyserver(path, id, keyserver)
                Autobuild::Subprocess.run(
                    "autoproj", "osrepos",
                    *cmd_acquire_root, "gpg",
                    "--no-default-keyring",
                    "--keyserver", keyserver, "--keyring", path, "--recv-keys", id
                )
            end

            def add_named_key_from_url(path, url)
                run_tee_command(path, URI(url).read)
            rescue Errno::ENOENT, SocketError => e
                raise ConfigError, e.message
            end

            def add_anonymous_key_from_keyserver(id, keyserver)
                Autobuild::Subprocess.run(
                    "autoproj", "osrepos",
                    *cmd_acquire_root, "apt-key", "adv",
                    "--keyserver", keyserver, "--recv-key", id
                )
            end

            def add_anonymous_key_from_url(url)
                URI(url).open do |io|
                    Autobuild::Subprocess.run(
                        "autoproj", "osrepos",
                        *cmd_acquire_root, "apt-key", "add", "-",
                        input_streams: [io]
                    )
                end
            rescue Errno::ENOENT, SocketError => e
                raise ConfigError, e.message
            end
        end
    end
end
