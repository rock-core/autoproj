module Autoproj
    module Ops
        # Common logic to generate build/import/utility reports
        class PhaseReporting
            def initialize(name, path, metadata_get)
                @name = name
                @path = path
                @metadata_get = metadata_get
            end

            def create_report(autobuild_packages)
                info = autobuild_packages.each_with_object({}) do |p, map|
                    map[p.name] = @metadata_get.call(p)
                end

                dump = JSON.dump(
                    "#{@name}_report" => {
                        "timestamp" => Time.now,
                        "packages" => info
                    }
                )

                FileUtils.mkdir_p File.dirname(@path)
                File.open(@path, "w") do |io|
                    io.write dump
                end
            end

            def initialize_incremental_report
                FileUtils.mkdir_p File.dirname(@path)
                @incremental_report = ""
            end

            def report_incremental(autobuild_package)
                new_metadata = @metadata_get.call(autobuild_package)
                prefix = @incremental_report.empty? ? "\n" : ",\n"
                @incremental_report.concat(
                    "#{prefix}\"#{autobuild_package.name}\": #{JSON.dump(new_metadata)}"
                )
                File.open(@path, "w") do |io|
                    io.write "{ \"#{@name}_report\": "\
                             "{\"timestamp\": #{JSON.dump(Time.now)}, \"packages\": {"
                    io.write(@incremental_report)
                    io.write "}}}"
                end
            end
        end
    end
end
