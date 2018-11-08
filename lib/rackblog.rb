require_relative "rackblog/server"
require_relative "rackblog/tags"
require_relative "rackblog/util"

module Rackblog
  class << self
    attr_accessor :config
  end
end