# = webgen extensions directory
#
# All init.rb files anywhere under this directory get automatically loaded on a webgen run. This
# allows you to add your own extensions to webgen or to modify webgen's core!
#
# If you don't need this feature you can savely delete this file and the directory in which it is!
#
# The +config+ variable below can be used to access the Webgen::Configuration object for the current
# website.
config = Webgen::WebsiteAccess.website.config

config = Webgen::WebsiteAccess.website.config
config['sourcehandler.patterns']['Webgen::SourceHandler::Copy'] << '**/*.sh'

$LOAD_PATH.unshift File.expand_path('..', File.dirname(__FILE__))
require 'ext/rdoc_links'
require 'ext/previous_next'
