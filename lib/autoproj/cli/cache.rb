require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Cache < InspectionTool
            def parse_options(argv)
                options = Hash[
                    keep_going: false
                ]
                opt = OptionParser.new do |opt|
                    opt.banner = "autoproj cache CACHE_DIR"
                    opt.on '-k', '--keep-going' do
                        options[:keep_going] = true
                    end
                end
                common_options(opt)
                cache_dir = opt.parse(argv)
                if cache_dir.empty?
                    raise ArgumentError, "expected one cache directory as argument"
                elsif cache_dir.size > 1
                    raise ArgumentError, "expected one cache directory as argument"
                end

                return File.expand_path(cache_dir.first, ws.root_dir), options
            end

            def run(cache_dir, options = Hash.new)
                options = validate_options options,
                    keep_going: false

                cache_op = Autoproj::Ops::Cache.new(cache_dir, ws.manifest)
                cache_op.create_or_update(options[:keep_going])
            end
        end
    end
end

