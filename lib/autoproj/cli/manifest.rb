require 'autoproj'
require 'autoproj/cli/base'
module Autoproj
    module CLI
        class Manifest < Base
            def validate_options(args, options)
                return args, options
            end

            def run(name, options = Hash.new)
                ws.load_config
                if name.empty?
                    Autoproj.message "current manifest is #{ws.manifest_file_path}"
                elsif name.size == 1
                    name = name.first
                    if File.file?(full_path = File.expand_path(name))
                        if File.dirname(full_path) != ws.config_dir
                            raise ArgumentError, "#{full_path} is not part of #{ws.config_dir}"
                        end
                    else
                        full_path = File.join(ws.config_dir, name)
                    end

                    if !File.file?(full_path)
                        alternative_full_path = File.join(ws.config_dir, "manifest.#{name}")
                        if !File.file?(alternative_full_path)
                            raise ArgumentError, "neither #{full_path} nor #{alternative_full_path} exist"
                        end
                        full_path = alternative_full_path
                    end
                    begin
                        Autoproj::Manifest.new(ws).load(full_path)
                    rescue Exception
                        Autoproj.error "failed to load #{full_path}"
                        raise
                    end
                    ws.config.set 'manifest_name', File.basename(full_path)
                    ws.save_config
                    Autoproj.message "set manifest to #{full_path}"
                else
                    raise ArgumentError, "expected zero or one argument, but got #{name.size}"
                end
            end
        end
    end
end

