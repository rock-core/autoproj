module Autoproj
    module AutobuildExtensions
        module SVN
            def snapshot(package, target_dir = nil, options = Hash.new)
                version = svn_revision(package)
                Hash["revision" => version]
            end
        end
    end
end
