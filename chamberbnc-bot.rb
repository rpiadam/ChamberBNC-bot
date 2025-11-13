#!/usr/bin/env ruby
####
## chamberBNC administration bot
##

## MIT License
## See LICENSE file for details.
####

$:.unshift File.dirname(__FILE__)

require 'cinch'
require 'cinch/plugins/identify'
require 'yaml'
require 'psych'
require 'fileutils'
require 'lib/requests'
require 'lib/relay'
require 'lib/logger'
require 'lib/mail'

ROOT_DIR   = File.expand_path(__dir__)
LOG_DIR    = File.join(ROOT_DIR, 'log')
CONFIG_PATH = ENV.fetch('CHAMBERBNC_CONFIG', File.join(ROOT_DIR, 'config', 'config.yaml'))

def abort_with_config_error(message)
  warn "[config] #{message}"
  exit 1
end

def load_config(path)
  raw = File.read(path)
  if Psych.respond_to?(:safe_load)
    Psych.safe_load(raw, permitted_classes: [], permitted_symbols: [], aliases: true) || {}
  else
    YAML.safe_load(raw, [], [], true) || {}
  end
rescue Errno::ENOENT
  abort_with_config_error("Configuration file not found at #{path}")
rescue Psych::SyntaxError => e
  abort_with_config_error("Failed to parse configuration: #{e.message}")
end

def ensure_hash!(hash, key, context = 'root')
  value = hash[key]
  abort_with_config_error("Missing #{context} value for '#{key}'") unless value.is_a?(Hash)
  value
end

def ensure_presence!(hash, key, context = 'root')
  value = hash[key]
  abort_with_config_error("Missing #{context} value for '#{key}'") if value.nil? || value.to_s.strip.empty?
  value
end

def normalize_channels(channels)
  Array(channels)
    .compact
    .map(&:to_s)
    .reject(&:empty?)
    .map { |channel| channel.start_with?('#') ? channel : "##{channel}" }
    .uniq
end

def validate_config!(config)
  bot_config   = ensure_hash!(config, 'bot')
  admin_config = ensure_hash!(config, 'admin')
  servers      = ensure_hash!(config, 'servers')
  znc_servers  = ensure_hash!(config, 'zncservers')

  %w[nick user realname channels].each do |key|
    ensure_presence!(bot_config, key, 'bot')
  end

  ensure_presence!(bot_config, 'saslname', 'bot')
  ensure_presence!(bot_config, 'saslpass', 'bot')

  ensure_presence!(config, 'requestdb')
  ensure_presence!(admin_config, 'network', 'admin')
  ensure_presence!(admin_config, 'channel', 'admin')

  servers.each do |name, server|
    abort_with_config_error("Server '#{name}' must be a Hash") unless server.is_a?(Hash)
    server_name = ensure_presence!(server, 'server', "server[#{name}]")
    port_value = ensure_presence!(server, 'port', "server[#{name}]")
    abort_with_config_error("Port for server '#{name}' must be numeric") unless Integer(port_value) rescue false
    server['server'] = server_name
    server['port'] = Integer(port_value)
    server['ssl'] = !!server['ssl']
  end

  znc_servers.each do |name, server|
    abort_with_config_error("ZNC server '#{name}' must be a Hash") unless server.is_a?(Hash)
    ensure_presence!(server, 'addr', "zncserver[#{name}]")
    ensure_presence!(server, 'username', "zncserver[#{name}]")
    ensure_presence!(server, 'password', "zncserver[#{name}]")
    port_value = ensure_presence!(server, 'port', "zncserver[#{name}]")
    abort_with_config_error("Port for ZNC server '#{name}' must be numeric") unless Integer(port_value) rescue false
    server['port'] = Integer(port_value)
    server['ssl'] = !!server['ssl']
  end

  config['bot']['channels'] = normalize_channels(bot_config['channels'])
  config['admin']['channel'] = config['admin']['channel'].to_s.start_with?('#') ? config['admin']['channel'] : "##{config['admin']['channel']}"

  relay_config = config['relay']
  if relay_config.nil?
    config['relay'] = { 'channels' => ['#bnc.im'] }
  elsif !relay_config.is_a?(Hash)
    abort_with_config_error("Relay configuration must be a Hash")
  else
    channels = normalize_channels(relay_config['channels'])
    if relay_config.key?('channels') && channels.empty?
      abort_with_config_error("relay.channels must include at least one channel")
    end
    relay_config['channels'] = channels.empty? ? ['#bnc.im'] : channels
  end

  config
end

def plugin_list_for(sasl_enabled)
  plugins = [RelayPlugin, RequestPlugin]
  plugins << Cinch::Plugins::Identify unless sasl_enabled
  plugins
end

$config = validate_config!(load_config(CONFIG_PATH))
$bots = {}
$zncs = {}

FileUtils.mkdir_p(LOG_DIR)

bot_config = $config.fetch('bot')
admin_config = $config.fetch('admin')
relay_channels = $config.fetch('relay').fetch('channels').dup.freeze

# Set up a bot for each server
$config['servers'].each do |name, server|
  channels = $config['bot']['channels'].dup
  if admin_config['network'] == name && !channels.include?(admin_config['channel'])
    channels << admin_config['channel']
  end

  sasl_enabled = server['sasl'] != false
  if sasl_enabled && (bot_config['saslname'].to_s.empty? || bot_config['saslpass'].to_s.empty?)
    abort_with_config_error("SASL is enabled for server '#{name}' but credentials are missing")
  end

  bot = Cinch::Bot.new do
    configure do |c|
      c.nick = bot_config['nick']
      c.user = bot_config['user']
      c.realname = bot_config['realname']
      c.server = server['server']
      c.ssl.use = server['ssl']
      c.port = server['port']
      c.channels = channels
      if sasl_enabled
        c.sasl.username = bot_config['saslname']
        c.sasl.password = bot_config['saslpass']
      end
      c.plugins.plugins = plugin_list_for(sasl_enabled)
      c.plugins.options[RelayPlugin] = {
        relay_channels: relay_channels.dup
      }
      unless sasl_enabled
        c.plugins.options[Cinch::Plugins::Identify] = {
          username: bot_config['saslname'],
          password: bot_config['saslpass'],
          type: :nickserv
        }
      end
    end
  end

  bot.loggers.clear
  bot.loggers << BNCLogger.new(name, File.open(File.join(LOG_DIR, "irc-#{name}.log"), 'a'))
  bot.loggers << BNCLogger.new(name, STDOUT)
  bot.loggers.level = :info

  $adminbot = bot if admin_config['network'] == name
  $bots[name] = bot
end

# Set up the ZNC bots
$config['zncservers'].each do |name, server|
  password = "#{server['username']}:#{server['password']}"
  bot = Cinch::Bot.new do
    configure do |c|
      c.nick = 'bncbot'
      c.server = server['addr']
      c.ssl.use = server['ssl']
      c.password = password
      c.port = server['port']
    end
  end

  bot.loggers.clear
  bot.loggers << BNCLogger.new(name, File.open(File.join(LOG_DIR, "znc-#{name}.log"), 'a'))
  bot.loggers << BNCLogger.new(name, STDOUT)
  bot.loggers.level = :info

  $zncs[name] = bot
end

# Initialize the RequestDB
RequestDB.load($config['requestdb'])

threads = []

$zncs.each_value do |bot|
  threads << Thread.new { bot.start }
end

$bots.each_value do |bot|
  threads << Thread.new { bot.start }
end

threads.each(&:join)
