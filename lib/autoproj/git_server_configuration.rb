module Autoproj
    GIT_SERVER_CONFIG_VARS = %w[_ROOT _PUSH_ROOT _PRIVATE_ROOT]

    GIT_SERVER_ACCESS_METHODS = Hash[
        "git" => "git,ssh",
        "ssh" => "ssh,ssh",
        "http" => "http,http"]

    # @api private
    #
    # Helper for {.git_server_configuration}
    def self.git_server_validate_config_value(base_url, value, disabled_methods:)
        values = (GIT_SERVER_ACCESS_METHODS[value] || value).split(",")
        values.each do |access_method|
            if !GIT_SERVER_ACCESS_METHODS.has_key?(access_method)
                raise Autoproj::InputError, "#{access_method} is not a known access method"
            elsif disabled_methods.include?(access_method)
                raise Autoproj::InputError, "#{access_method} is disabled on #{base_url}"
            end
        end
        value
    end

    # @api private
    #
    # Helper for {.git_server_configuration}
    def self.git_server_resolve_master_config(name, config, base_url:, git_url:, http_url:, ssh_url:, disabled_methods:)
        access_mode = config.get(name)
        begin
            git_server_validate_config_value(base_url, access_mode, disabled_methods: disabled_methods)
        rescue Autoproj::InputError => e
            Autoproj.warn e.message
            config.reset(name)
            access_mode = config.get(name)
        end
        access_mode = GIT_SERVER_ACCESS_METHODS[access_mode] || access_mode
        pull, push, private_pull = access_mode.split(",")
        private_pull ||= push
        [[pull, "_ROOT"], [push, "_PUSH_ROOT"], [private_pull, "_PRIVATE_ROOT"]].each do |method, var_suffix|
            url = if method == "git" then git_url
                  elsif method == "http" then http_url
                  elsif method == "ssh" then ssh_url
                  end
            config.set("#{name}#{var_suffix}", url)
        end
        [pull, push, private_pull]
    end

    # Adds the relevant options to handle a gitorious server
    # What this does is ask the user how he would like to access the gitorious
    # server. Then, it sets
    #
    #   #{name}_ROOT to be the base URL for pulling
    #   #{name}_PUSH_ROOT to be the corresponding ssh-based URL for pushing
    #
    # For instance, with
    #
    #   git_server_configuration "GITHUB", "github.com"
    #
    #
    # One would use the following shortcut in its source.yml:
    #
    #   - my/package:
    #     github: account/package
    #
    # which would be expanded to the expected URLs for pull and push.
    #
    def self.git_server_configuration(name, base_url,
        git_url: "git://#{base_url}",
        http_url: "https://git.#{base_url}",
        ssh_url: "git@#{base_url}:",
        default: "http,ssh",
        disabled_methods: [],
        config: Autoproj.config,
        fallback_to_http: nil,
        lazy: false,
        add_suffix: true)

        disabled_methods = Array(disabled_methods)

        long_doc = [
            "How should I interact with #{base_url} (#{(GIT_SERVER_ACCESS_METHODS.keys - disabled_methods).sort.join(', ')})",
            "If you give one value, it's going to be the method used for all access",
            "If you give multiple values, comma-separated, the first one will be",
            "used for pulling and the second one for pushing. An optional third value",
            "will be used to pull from private repositories (the same than pushing is",
            "used by default)"
        ]

        config.declare name, "string", default: default, doc: long_doc do |value|
            git_server_validate_config_value(base_url, value, disabled_methods: disabled_methods)
        end

        unless lazy
            pull, push, private_pull = git_server_resolve_master_config(name, config,
                                                                        base_url: base_url,
                                                                        git_url: git_url,
                                                                        http_url: http_url,
                                                                        ssh_url: ssh_url,
                                                                        disabled_methods: disabled_methods)
        end

        Autoproj.add_source_handler name.downcase do |url, private: false, **vcs_options|
            if add_suffix
                url += ".git" if url !~ /\.git$/
            end
            url = "/#{url}" if url !~ /^\//

            unless GIT_SERVER_CONFIG_VARS.all? { |v| config.has_value_for?("#{name}#{v}") }
                pull, push, private_pull = git_server_resolve_master_config(name, config,
                                                                            base_url: base_url,
                                                                            git_url: git_url,
                                                                            http_url: http_url,
                                                                            ssh_url: ssh_url,
                                                                            disabled_methods: disabled_methods)
            end
            pull_base_url =
                if private
                    config.get("#{name}_PRIVATE_ROOT")
                else
                    config.get("#{name}_ROOT")
                end
            push_base_url = config.get("#{name}_PUSH_ROOT")
            Hash[type: "git",
                 url: "#{pull_base_url}#{url}",
                 push_to: "#{push_base_url}#{url}",
                 interactive: (private && private_pull == "http"),
                 retry_count: 10,
                 repository_id: "#{name.downcase}:#{url}"].merge(vcs_options)
        end
    end

    def self.gitorious_server_configuration(name, base_url, **options)
        Autoproj.warn_deprecated "gitorious_server_configuration",
                                 "use require 'git_server_configuration' and
            Autoproj.git_server_configuration instead. note that the method call
            interface has not changed, you just have to change the name(s)"
        git_server_configuration(name, base_url, **options)
    end
end

unless $autoproj_disable_github_gitorious_definitions
    Autoproj.git_server_configuration("GITORIOUS", "gitorious.org", default: "http,ssh", disabled_methods: "git", lazy: true)
    Autoproj.git_server_configuration("GITHUB", "github.com", http_url: "https://github.com", default: "http,ssh")
end
