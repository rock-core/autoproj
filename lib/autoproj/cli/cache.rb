require 'autoproj/cli/inspection_tool'
require 'autoproj/ops/cache'

module Autoproj
    module CLI
        class Cache < InspectionTool
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
                        name, *artifacts = name.split('+')
                        [name, artifacts: artifacts]
                    end
                end

                [File.expand_path(argv.first, ws.root_dir), *argv[1..-1], options]
            end

            def run(cache_dir, *package_names,
                    keep_going: false,
                    packages: true, all: true, checkout_only: false,
                    gems: false, gems_compile: [])
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
                        compile: gems_compile
                    )
                end
            end
        end
    end
end

