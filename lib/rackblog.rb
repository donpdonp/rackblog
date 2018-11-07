require_relative "rackblog/server"
require_relative "rackblog/tags"

module Rackblog
  class << self
    attr_accessor :config
  end
end