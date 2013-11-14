#!/usr/bin/env ruby
####
## bnc.im administration bot
##
## Copyright (c) 2013 Andrew Northall
##
## MIT License
## See LICENSE file for details.
####

$:.unshift File.dirname(__FILE__)

require 'cinch'
require 'yaml'
require 'lib/requests'

$config = YAML.load_file("config/config.yaml")
$bots = Hash.new
$threads = Array.new

# Set up a bot for each server
$config["servers"].each do |name, server|
  bot = Cinch::Bot.new do
    configure do |c|
      c.nick = "bncim-test"
      c.user = "bncim"
      c.realname = "bnc.im administration bot"
      c.server = server["server"]
      c.ssl.use = server["ssl"]
      c.sasl.username = "bncim"
      c.sasl.password = $config["nickserv-password"]
      c.port = server["port"]
      c.channels = ["#bnc.im-admin"]
      c.plugins.plugins = [RequestPlugin]
    end
  end
  bot.loggers << Cinch::Logger::FormattedLogger.new(File.open("log/#{name}.log", "a"))
  bot.loggers.level = :info
  $bots[name] = bot
end

# Initialize the RequestDB
RequestDB.load($config["requestdb"])

# Start the bots
$bots.each do |key, bot|
  puts "Starting #{key} bot..."
  $threads << Thread.new { bot.start }
end

$threads.each { |t| t.join } # wait for other threads