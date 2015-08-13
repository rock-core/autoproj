module Autoproj
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
    def self.git_server_configuration(name, base_url, options = Hash.new)
        options = Kernel.validate_options options,
            git_url: "git://#{base_url}",
            http_url: "https://git.#{base_url}",
            ssh_url: "git@#{base_url}:",
            default: 'http,ssh',
            disabled_methods: [],
            config: Autoproj.config,
            fallback_to_http: nil

        config = options.delete(:config)
        disabled_methods = Array(options[:disabled_methods])

        access_methods = Hash[
            'git' => 'git,ssh',
            'ssh' => 'ssh,ssh',
            'http' => 'http,http']

        gitorious_long_doc = [
            "How should I interact with #{base_url} (#{(access_methods.keys - disabled_methods).sort.join(", ")})",
            "If you give one value, it's going to be the method used for all access",
            "If you give multiple values, comma-separated, the first one will be",
            "used for pulling and the second one for pushing. An optional third value",
            "will be used to pull from private repositories (the same than pushing is",
            "used by default)"]

        validator = lambda do |value|
            values = (access_methods[value] || value).split(",")
            values.each do |access_method|
                if !access_methods.has_key?(access_method)
                    raise Autoproj::InputError, "#{access_method} is not a known access method"
                elsif disabled_methods.include?(access_method)
                    raise Autoproj::InputError, "#{access_method} is disabled on #{base_url}"
                end
            end
            value
        end

        config.declare name, 'string',
            default: options[:default],
            doc: gitorious_long_doc, &validator

        access_mode = config.get(name)
        begin
            validator[access_mode]
        rescue Autoproj::InputError => e
            Autoproj.warn e.message
            config.reset(name)
            access_mode = config.get(name)
        end
        access_mode = access_methods[access_mode] || access_mode
        pull, push, private_ull = access_mode.split(',')
        private_pull ||= push
        [[pull, "_ROOT"], [push, "_PUSH_ROOT"], [private_pull, "_PRIVATE_ROOT"]].each do |method, var_suffix|
            url = if method == "git" then options[:git_url]
                  elsif method == "http" then options[:http_url]
                  elsif method == "ssh" then options[:ssh_url]
                  end
            config.set("#{name}#{var_suffix}", url)
        end

        Autoproj.add_source_handler name.downcase do |url, vcs_options|
            if url !~ /\.git$/
                url += ".git"
            end
            if url !~ /^\//
                url = "/#{url}"
            end
            pull_base_url =
                if vcs_options[:private]
                    config.get("#{name}_PRIVATE_ROOT")
                else
                    config.get("#{name}_ROOT")
                end
            push_base_url = config.get("#{name}_PUSH_ROOT")
            Hash[type: 'git',
                 url: "#{pull_base_url}#{url}",
                 push_to: "#{push_base_url}#{url}",
                 retry_count: 10,
                 repository_id: "#{name.downcase}:#{url}"].merge(vcs_options)
        end
    end

    def self.gitorious_server_configuration(name, base_url, options = Hash.new)
        Autoproj.warn "gitorious_server_configuration is deprecated, replace by git_server_configuration"
        Autoproj.warn "Note that the call interface has not changed, you only need to change the method name"
        git_server_configuration(name, base_url, options)
    end
end

Autoproj.git_server_configuration('GITORIOUS', 'gitorious.org', default: 'http,ssh', disabled_methods: 'git')
Autoproj.git_server_configuration('GITHUB', 'github.com', http_url: 'https://github.com', default: 'http,ssh')

