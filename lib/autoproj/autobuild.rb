require "autoproj/autobuild_extensions/package"
require "autoproj/autobuild_extensions/archive_importer"
require "autoproj/autobuild_extensions/git"
require "autoproj/autobuild_extensions/svn"
require "autoproj/autobuild_extensions/dsl"

Autobuild::Package.class_eval do
    prepend Autoproj::AutobuildExtensions::Package
end
Autobuild::ArchiveImporter.class_eval do
    prepend Autoproj::AutobuildExtensions::ArchiveImporter
end
Autobuild::Git.class_eval do
    prepend Autoproj::AutobuildExtensions::Git
end
Autobuild::SVN.class_eval do
    prepend Autoproj::AutobuildExtensions::SVN
end
