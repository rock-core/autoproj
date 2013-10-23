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
            :fallback_to_http => true

        gitorious_long_doc = [
            "Access method to import data from #{base_url} (git, http or ssh)",
            "Use 'ssh' only if you have an account there. Note that",
            "ssh will always be used to push to the repositories, this is",
            "only to get data from the server. Therefore, we advise to use",
            "'git' as it is faster than ssh and better than http"]

        configuration_option name, 'string',
            :default => "git",
            :values => ["http", "ssh"],
            :doc => gitorious_long_doc do |value|

            value
        end

        access_mode = Autoproj.user_config(name)
        if access_mode == "git"
            Autoproj.change_option("#{name}_ROOT", "git://#{base_url}")
        elsif access_mode == "http"
            Autoproj.change_option("#{name}_ROOT", "https://git.#{base_url}")
        elsif access_mode == "ssh"
            Autoproj.change_option("#{name}_ROOT", "git@#{base_url}:")
        end
        Autoproj.change_option("#{name}_PUSH_ROOT", "git@#{base_url}:")

        Autoproj.add_source_handler name.downcase do |url, options|
            if url !~ /\.git$/
                url += ".git"
            end
            if url !~ /^\//
                url = "/#{url}"
            end
            pull_base_url = Autoproj.user_config("#{name}_ROOT")
            push_base_url = Autoproj.user_config("#{name}_PUSH_ROOT")
            Hash[:type => 'git', :url => "#{pull_base_url}#{url}", :push_to => "#{push_base_url}#{url}", :retry_count => 10].merge(options)
        end
    end
end

