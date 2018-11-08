require 'set'
require 'json'
require 'slim'
require 'lmdb'
require 'httparty'
require 'github/markdown'
require 'atom/feed'
require 'nokogiri'

Dir.glob("lib/rackblog/*.rb").each do |file|
  parts = file.split('/')
  parts.shift
  require_relative parts.join('/')
end

module Rackblog
  class << self
    attr_accessor :Config, :Db, :Tags, :Mentions
  end
end