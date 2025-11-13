####
### chamberbnc administration bot
### logger
###
### Copyright (c) 2022 Andrew Northall
###
### MIT License
### See LICENSE file for details.
#####

require 'cinch'
require 'time'

class BNCLogger < Cinch::Logger::FormattedLogger
  def initialize(network, device, level: :info, timestamp: true)
    @network = network
    @timestamp_enabled = timestamp
    super(device)
    self.level = level
  end

  def format_general(message)
    message.gsub!(/[^[:print:][:space:]]/) do |m|
      colorize(m.inspect[1..-2], :bg_white, :black)
    end

    formatted = +"[#{@network}] #{message}"
    formatted.prepend("#{timestamp_prefix} ") if timestamp_enabled?
    formatted
  end

  private

  attr_reader :timestamp_enabled

  def timestamp_enabled?
    timestamp_enabled
  end

  def timestamp_prefix
    Time.now.utc.iso8601
  end
end

