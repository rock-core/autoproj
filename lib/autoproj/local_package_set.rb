module Autoproj
    # Specialization of the PackageSet class to handle the "master" package set
    # in autoproj/
    class LocalPackageSet < PackageSet
        def initialize(ws, local_dir: ws.config_dir)
            super(ws, VCSDefinition.none, name: "main configuration", raw_local_dir: local_dir)
            @local_dir = local_dir
        end

        def vcs
            ws.manifest.vcs
        end

        def main?
            true
        end

        def local?
            true
        end

        def local_dir
            raw_local_dir
        end

        def manifest_path
            manifest.file
        end

        def overrides_file_path
            if (d = local_dir)
                File.join(d, "overrides.yml")
            end
        end

        def source_file
            overrides_file_path
        end

        # Reimplemented from {PackageSet#load_description_file} to remove the
        # name validation
        def load_description_file
            source_definition = raw_description_file
            parse_source_definition(source_definition)
        end

        # Load the files in overrides.d in addition to the overrides: field in
        # the yaml file
        def load_overrides(source_definition)
            files = Dir.glob(File.join(ws.overrides_dir, "*.yml")).sort
            overrides = files.map do |file|
                source_data = Autoproj.in_file(file, Autoproj::YAML_LOAD_ERROR) do
                    YAML.load(File.read(file)) || Array.new
                end
                source_data =
                    if source_data.respond_to?(:to_ary)
                        source_data
                    else
                        source_data["overrides"] || Hash.new
                    end
                [file, source_data]
            end
            overrides + super
        end

        def raw_description_file
            description = Hash[
                "imports" => Array.new,
                "version_control" => Array.new,
                "overrides" => Array.new]
            if File.file?(overrides_file_path)
                overrides_data = Autoproj.in_file(overrides_file_path, Autoproj::YAML_LOAD_ERROR) do
                    YAML.load(File.read(overrides_file_path)) || Hash.new
                end
                overrides_data = PackageSet.validate_and_normalize_source_file(
                    overrides_file_path, overrides_data
                )
                description = description.merge(overrides_data)
            end

            manifest_data = Autoproj.in_file(manifest_path, Autoproj::YAML_LOAD_ERROR) do
                YAML.load(File.read(manifest_path)) || Hash.new
            end
            if !manifest_data["package_sets"].is_a?(Array)
                raise SyntaxError.new "The package_sets field in your manifest file is not an array, check your YAML syntax"
            end
            description["imports"] = description["imports"]
                                     .concat(manifest_data["package_sets"] || Array.new)
            description["name"] = name
            description
        end
    end
end
