require "enumerator"
require 'autobuild'
require 'autoproj/base'
require 'autoproj/version'
require 'autoproj/environment'
require 'autoproj/variable_expansion'
require 'autoproj/vcs_definition'
require 'autoproj/package_set'
require 'autoproj/package_definition'
require 'autoproj/package_selection'
require 'autoproj/metapackage'
require 'autoproj/manifest'
require 'autoproj/package_manifest'
require 'autoproj/installation_manifest'
require 'autoproj/osdeps'
require 'autoproj/system'
require 'autoproj/build_option'
require 'autoproj/configuration'
require 'autoproj/options'
# Required for auto-saving in import_packages
require 'autoproj/ops/snapshot'
require 'autoproj/cmdline'
require 'autoproj/query'

require 'autoproj/ops/tools'
require 'autoproj/ops/loader'
require 'autoproj/ops/configuration'

require 'autoproj/workspace'

require 'logger'
require 'utilrb/logger'

module Autoproj
    class << self
        attr_reader :logger
    end
    @logger = Logger.new(STDOUT)
    logger.level = Logger::WARN
    logger.formatter = lambda { |severity, time, progname, msg| "#{severity}: #{msg}\n" }
    extend Logger::Forward

    def self.warn_deprecated(method, msg)
        Autoproj.warn "#{method} is deprecated, #{msg}"
        caller.each { |l| Autoproj.warn "  #{l}" }
    end
end

