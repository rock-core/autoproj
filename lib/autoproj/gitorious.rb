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
    def gitorious_server_configuration(name, base_url, options = Hash.new)
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
            Autoproj.change_option("#{name}_ROOT", "http://git.#{base_url}")
        elsif access_mode == "ssh"
            Autoproj.change_option("#{name}_ROOT", "git@#{base_url}:")
        end
        Autoproj.change_option("#{name}_PUSH_ROOT", "git@#{base_url}:")

        # If running on a recent enough autobuild version, register a fallback to
        # use http when git fails
        if Autobuild::Importer.respond_to?(:fallback) && options[:fallback_to_http]
            Autobuild::Importer.fallback do |package, importer|
                root_rx = /^(?:http:\/\/git\.|git:\/\/|git@)#{Regexp.quote(base_url)}/
                if importer.kind_of?(Autobuild::Git) && importer.repository =~ root_rx && importer.repository !~ /^http/
                    Autoproj.warn "import from #{importer.repository} failed, falling back to using http for all packages on #{base_url}"
                    Autobuild::Package.each do |pkg_name, pkg|
                        if pkg.importer.kind_of?(Autobuild::Git) && pkg.importer.repository =~ root_rx
                            pkg.importer.repository.gsub!(root_rx, "http://git.#{base_url}")
                        end
                    end

                    http_importer = importer.dup
                    http_importer.repository = importer.repository.gsub(root_rx, "http://git.#{base_url}")
                    http_importer
                end
            end
        end
    end
end

