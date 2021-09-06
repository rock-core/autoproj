require "autoproj/cli/main"
require "erb"

module Autoproj
    # Generates shell completion for code for a given Thor subclass
    class ShellCompletion
        # The CLI
        attr_reader :cli
        # The command name
        attr_reader :name
        # A hash describing the CLI
        attr_reader :cli_metadata

        TEMPLATES_DIR = File.join(File.dirname(__FILE__), "templates")

        def initialize(name = "autoproj", cli: Autoproj::CLI::Main, command: nil)
            @cli = cli
            @name = name

            generate_metadata
            return unless command
            @cli_metadata = subcommand_by_name(*command)
            @cli_metadata[:name] = "__#{name}"
        end

        def generate_metadata
            @cli_metadata = { name: "__#{name}",
                              description: nil,
                              options: [],
                              subcommands: subcommand_metadata(cli) }

            setup_completion_functions
            populate_help_subcommands
        end

        def setup_completion_functions
            %w[which exec].each do |command|
                setup_executable_completion(subcommand_by_name(command))
            end

            %w[cache manifest].each do |command|
                setup_file_completion(subcommand_by_name(command))
            end

            # TODO: investigate how to handle 'plugin' subcommands completion,
            # leaving disabled for now
            # TODO: reset subcommand needs a custom completer,
            # leaving disabled for now
            # TODO: log subcommand needs a custom completer,
            # leaving disabled for now
            ["bootstrap", "envsh", "reconfigure", "reset", "log", "query",
             "switch-config", %w[global register], %w[global status],
             %w[plugin install], %w[plugin remove], %w[plugin list]].each do |command|
                disable_completion(subcommand_by_name(*command))
            end
        end

        def generate
            template_file = File.join(TEMPLATES_DIR, self.class::MAIN_FUNCTION_TEMPLATE)
            erb = File.read(template_file)
            ::ERB.new(erb, nil, "-").result(binding)
        end

        def subcommand_by_name(*name, metadata: cli_metadata)
            subcommand = metadata

            name.each do |subcommand_name|
                subcommand = subcommand[:subcommands].find do |s|
                    s[:name] == subcommand_name
                end
            end
            subcommand
        end

        def populate_help_subcommands(command_metadata = cli_metadata)
            help_subcommand = subcommand_by_name("help",
                                                 metadata: command_metadata)

            if help_subcommand
                help_subcommand[:options] = []
                disable_completion(help_subcommand)
            end

            command_metadata[:subcommands].each do |subcommand|
                next if subcommand[:name] == "help"
                populate_help_subcommands(subcommand)
                next unless help_subcommand
                help_subcommand[:subcommands] << { name: subcommand[:name],
                                                   aliases: [],
                                                   description: subcommand[:description],
                                                   options: [],
                                                   subcommands: [] }
            end
        end

        def render_subcommand_function(subcommand, options = {})
            prefix = options[:prefix] || []
            source = []

            prefix = (prefix + [subcommand[:name]])
            function_name = prefix.join("_")
            depth = prefix.size + 1

            template_file = File.join(TEMPLATES_DIR, self.class::SUBCOMMAND_FUNCTION_TEMPLATE)
            erb = ::ERB.new(File.read(template_file), nil, "-")

            source << erb.result(binding)
            subcommand[:subcommands].each do |subcommand|
                source << render_subcommand_function(subcommand, prefix: prefix)
            end
            "#{source.join("\n").strip}\n"
        end

        def subcommand_metadata(cli)
            result = []
            cli.all_commands.reject { |_, t| t.hidden? }.each do |(name, command)|
                aliases = cli.map.select do |_, original_name|
                    name == original_name
                end.map(&:first)
                result << generate_command_metadata(cli, name, command, aliases)
            end
            result
        end

        def generate_command_metadata(cli, name, command, aliases)
            subcommands = if (subcommand_class = cli.subcommand_classes[name])
                              subcommand_metadata(subcommand_class)
                          else
                              []
                          end

            info = { name: hyphenate(name),
                     aliases: aliases.map { |a| hyphenate(a) },
                     usage: command.usage,
                     description: command.description,
                     options: options_metadata(cli.class_options) +
                              options_metadata(command.options),
                     subcommands: subcommands }

            if subcommands.empty?
                setup_package_completion(info)
            else
                info[:options] = []
                disable_completion(info)
            end
            info
        end

        def options_metadata(options)
            options.reject { |_, option| option.hide }.map do |_, option|
                names = ["--#{hyphenate(option.name)}"]
                names += ["--no-#{hyphenate(option.name)}"] if option.boolean?
                names += option.aliases.map { |a| "-#{hyphenate(a)}" }

                { names: names,
                  description: option.description }
            end
        end

        def hyphenate(s)
            s.to_s.tr("_", "-")
        end
    end
end
