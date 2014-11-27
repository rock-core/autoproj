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
    #   handle_gitorious_server "GITORIOUS", "gitorious.org"
    #
    # the URLs for the rtt repository in the orocos-toolchain gitorious project would
    # be defined in the source.yml files as
    #
    #   ${GITORIOUS_ROOT}/orocos-toolchain/rtt.git
    #   ${GITORIOUS_PUSH_ROOT}/orocos-toolchain/rtt.git
    #
    # Since it seems that the http method for gitorious servers is more stable, a
    # fallback importer is set up that falls back to using http for pulling as soon
    # as import failed
    def self.gitorious_server_configuration(name, base_url, options = Hash.new)
        options = Kernel.validate_options options,
            :git_url  => "git://#{base_url}",
            :http_url => "https://git.#{base_url}",
            :ssh_url  => "git@#{base_url}:",
            :fallback_to_http => true,
            :default => 'git,ssh'

        gitorious_long_doc = [
            "How should I interact with #{base_url} (git, http or ssh)",
            "If you give two values, comma-separated, the first one will be",
            "used for pulling and the second one for pushing"]

        access_methods = Hash[
            'git' => 'git,ssh',
            'ssh' => 'ssh,ssh',
            'http' => 'http,http']

        configuration_option name, 'string',
            :default => options[:default],
            :doc => gitorious_long_doc do |value|
                if value =~ /,/
                    value.split(',').each do |method|
                        if !access_methods.has_key?(method)
                            raise Autoproj::InputError, "#{method} is not a known access method"
                        end
                    end
                elsif !access_methods.has_key?(value)
                    raise Autoproj::InputError, "#{value} is not a known access method"
                end

                value
            end

        access_mode = Autoproj.user_config(name)
        access_mode = access_methods[access_mode] || access_mode
        pull, push = access_mode.split(',')
        [[pull, "_ROOT"], [push, "_PUSH_ROOT"]].each do |method, var_suffix|
            url = if method == "git" then options[:git_url]
                  elsif method == "http" then options[:http_url]
                  elsif method == "ssh" then options[:ssh_url]
                  end
            Autoproj.change_option("#{name}#{var_suffix}", url)
        end

        Autoproj.add_source_handler name.downcase do |url, vcs_options|
            if url !~ /\.git$/
                url += ".git"
            end
            if url !~ /^\//
                url = "/#{url}"
            end
            pull_base_url = Autoproj.user_config("#{name}_ROOT")
            push_base_url = Autoproj.user_config("#{name}_PUSH_ROOT")
            vcs_options.merge(
                type: 'git',
                url: "#{pull_base_url}#{url}",
                push_to: "#{push_base_url}#{url}",
                retry_count: 10,
                repository_id: "#{name.downcase}:#{url}")
        end
    end
end

Autoproj.gitorious_server_configuration('GITORIOUS', 'gitorious.org')
Autoproj.gitorious_server_configuration('GITHUB', 'github.com', :http_url => 'https://github.com', :default => 'http,ssh')

