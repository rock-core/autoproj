require "rexml/streamlistener"
require "utilrb/module/attr_predicate"
require "pathname"
require "concurrent"

require "backports/2.4.0/float/dup"
require "backports/2.4.0/fixnum/dup"
require "backports/2.4.0/nil_class/dup"
require "backports/2.4.0/false_class/dup"
require "backports/2.4.0/true_class/dup"
require "backports/2.4.0/hash/transform_values"
require "backports/2.5.0/hash/transform_keys"

require "autobuild"
require "autoproj/autobuild"
require "autoproj/base"
require "autoproj/exceptions"
require "autoproj/version"
require "autoproj/reporter"
require "autoproj/environment"
require "autoproj/variable_expansion"
require "autoproj/find_workspace"
require "autoproj/vcs_definition"
require "autoproj/package_set"
require "autoproj/local_package_set"
require "autoproj/package_definition"
require "autoproj/package_selection"
require "autoproj/metapackage"
require "autoproj/manifest"
require "autoproj/package_manifest"
require "autoproj/installation_manifest"
require "autoproj/os_package_installer"
require "autoproj/os_package_resolver"
require "autoproj/os_repository_resolver"
require "autoproj/os_repository_installer"
require "autoproj/system"
require "autoproj/build_option"
require "autoproj/configuration"
require "autoproj/options"
# Required by Workspace
require "autoproj/ops/import"
# Required for auto-saving in import_packages
require "autoproj/ops/snapshot"
require "autoproj/query_base"
require "autoproj/source_package_query"
require "autoproj/os_package_query"

require "autoproj/ops/phase_reporting"
require "autoproj/ops/install"
require "autoproj/ops/tools"
require "autoproj/ops/loader"
require "autoproj/ops/configuration"
require "autoproj/ops/cached_env"
require "autoproj/ops/which"
require "autoproj/ops/atomic_write"

require "autoproj/workspace"

require "logger"
require "utilrb/logger"

module Autoproj
    class << self
        attr_reader :logger
    end
    @logger = Logger.new(STDOUT)
    logger.level = Logger::WARN
    logger.formatter = lambda { |severity, time, progname, msg| "#{severity}: #{msg}\n" }
    extend Logger::Forward

    def self.warn_deprecated_level
        @warn_deprecated_level
    end

    def self.warn_deprecated_level=(level)
        @warn_deprecated_level = level
    end
    @warn_deprecated_level = 1

    def self.warn_deprecated(method, msg = nil, level = 0)
        if level >= @warn_deprecated_level
            if msg
                Autoproj.warn "#{method} is deprecated, #{msg}"
            else
                Autoproj.warn msg
            end
            caller.each { |l| Autoproj.warn "  #{l}" }
        end
    end
end
