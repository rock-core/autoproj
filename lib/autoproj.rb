module Autoproj
    class ConfigError < RuntimeError; end
    class InternalError < RuntimeError; end
end

require "enumerator"
require 'autoproj/version'
require 'autoproj/manifest'
require 'autoproj/osdeps'
require 'autoproj/system'
require 'autoproj/options'
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
end

