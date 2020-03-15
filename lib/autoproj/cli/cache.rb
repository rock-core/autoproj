# frozen_string_literal: true

require 'autoproj/cli/inspection_tool'
require 'autoproj/ops/cache'

module Autoproj
    module CLI
        class Cache < InspectionTool
            def parse_gem_compile(string)
                scanner = StringScanner.new(string)
                name = scanner.scan(/[^\[]+/)

                level = 0
                artifacts = []
                artifact_include = nil
                artifact_name = ''.dup
                until scanner.eos?
                    c = scanner.getch
                    if level == 0
                        raise ArgumentError, "expected '[' but got '#{c}'" unless c == '['

                        level = 1
                        include_c = scanner.getch
                        if %w[+ -].include?(include_c)
                            artifact_include = (include_c == '+')
                        elsif include_c == ']'
                            raise ArgumentError, "empty [] found in '#{string}'"
                        else
                            raise ArgumentError,
                                  "expected '+' or '-' but got '#{c}' in '#{string}'"
                        end
                        next
                    end

                    if c == ']'
                        level -= 1
                        if level == 0
                            artifacts << [artifact_include, artifact_name]
                            artifact_name = ''.dup
                            next
                        end
                    end

                    artifact_name << c
                end

                raise ArgumentError, "missing closing ']' in #{string}" if level != 0

                [name, artifacts: artifacts]
            end

            def validate_options(argv, options = Hash.new)
                argv, options = super

                if argv.empty?
                    default_cache_dirs = Autobuild::Importer.default_cache_dirs
                    if !default_cache_dirs || default_cache_dirs.empty?
                        raise CLIInvalidArguments,
                              "no cache directory defined with e.g. the "\
                              "AUTOBUILD_CACHE_DIR environment variable, "\
                              "expected one cache directory as argument"
                    end
                    Autoproj.warn "using cache directory #{default_cache_dirs.first} "\
                                  "from the autoproj configuration"
                    argv << default_cache_dirs.first
                end

                if (compile = options[:gems_compile])
                    options[:gems_compile] = compile.map do |name|
                        parse_gem_compile(name)
                    end
                end

                [File.expand_path(argv.first, ws.root_dir), *argv[1..-1], options]
            end

            def run(cache_dir, *package_names,
                    keep_going: false,
                    packages: true, all: true, checkout_only: false,
                    gems: false, gems_compile: [], gems_compile_force: false)
                initialize_and_load
                finalize_setup

                cache_op = Autoproj::Ops::Cache.new(cache_dir, ws)
                if packages
                    cache_op.create_or_update(
                        *package_names,
                        all: all, keep_going: keep_going,
                        checkout_only: checkout_only
                    )
                end

                if gems
                    Autoproj.message "caching gems in #{cache_op.gems_cache_dir}"
                    cache_op.create_or_update_gems(
                        keep_going: keep_going,
                        compile: gems_compile,
                        compile_force: gems_compile_force
                    )
                end
            end
        end
    end
end
