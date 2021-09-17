module Autoproj
    module AutobuildExtensions
        module ArchiveImporter
            # Reconfigures this importer to use an already existing checkout located
            # in the given autoproj root
            #
            # @param [Autobuild::Package] the package we are dealing with
            # @param [Autoproj::InstallationManifest] the other root's installation
            #   manifest
            def pick_from_autoproj_root(package, installation_manifest)
                # Get the cachefile w.r.t. the autoproj root
                cachefile = Pathname.new(self.cachefile)
                                    .relative_path_from(Pathname.new(ws.root_dir)).to_s

                # The cachefile in the other autoproj installation
                other_cachefile = File.join(installation_manifest.path, cachefile)
                if File.file?(other_cachefile)
                    relocate("file://#{other_cachefile}")
                    true
                end
            end

            def snapshot(package, target_dir = nil, options = Hash.new)
                result = Hash[
                    "mode" => mode,
                    "no_subdirectory" => !has_subdirectory?,
                    "archive_dir" => archive_dir || tardir]

                if target_dir
                    archive_dir = File.join(target_dir, "archives")
                    FileUtils.mkdir_p archive_dir
                    FileUtils.cp @cachefile, archive_dir

                    result["url"] = "file://$AUTOPROJ_SOURCE_DIR/archives/#{File.basename(@cachefile)}"
                else
                    result["url"] = @url.to_s
                end

                result
            end
        end
    end
end
