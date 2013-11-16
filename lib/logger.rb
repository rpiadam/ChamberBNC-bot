####
### bnc.im administration bot
### logger
###
### Copyright (c) 2013 Andrew Northall
###
### MIT License
### See LICENSE file for details.
#####

require 'cinch'

class BNCLogger < Cinch::Logger::FormattedLogger
  def initialize(network, *args)
    @network = network
    super(*args)
  end

  def format_general(message)
    message.gsub!(/[^[:print:][:space:]]/) do |m|
      colorize(m.inspect[1..-2], :bg_white, :black)
    end
    "[#{@network}] #{message}"
  end
end

