module Rubotics
    class ConfigError < RuntimeError; end
end

require "enumerator"
require 'rubotics/manifest'
require 'rubotics/osdeps'
require 'rubotics/system'
require 'logger'
require 'utilrb/logger'

module Rubotics
    class << self
        attr_reader :logger
    end
    @logger = Logger.new(STDOUT)
    logger.level = Logger::WARN
    logger.formatter = lambda { |severity, time, progname, msg| "#{severity}: #{msg}\n" }
    extend Logger::Forward
end

