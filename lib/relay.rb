class RelayPlugin
  include Cinch::Plugin

  DEFAULT_CHANNELS = ['#bnc.im'].freeze

  listen_to :message, method: :relay
  listen_to :leaving, method: :relay_part
  listen_to :join, method: :relay_join

  def initialize(*args)
    super
    configured_channels = Array(config[:relay_channels])
    @relay_channels = normalize_channels(configured_channels)
    @relay_channels = DEFAULT_CHANNELS.dup if @relay_channels.empty?
    @normalized_channels = @relay_channels.map { |channel| channel.downcase }
  end

  def relay(m)
    channel = channel_name(m.channel)
    return unless relay_channel?(channel)
    return if from_self?(m.user)

    send_relay(format_message(m), channel)
  end

  def relay_part(m)
    channel = channel_name(m.channel)
    return unless relay_channel?(channel) || m.command == 'QUIT'
    return if from_self?(m.user)

    action = case m.command
             when 'PART' then "parted #{channel || default_channel}"
             when 'QUIT' then 'quit'
             else "left #{channel || default_channel}"
             end

    message = "#{network_prefix} - #{m.user.nick} has #{action}."
    send_relay(message, channel)
  end

  def relay_join(m)
    channel = channel_name(m.channel)
    return unless relay_channel?(channel)
    return if from_self?(m.user)

    message = "#{network_prefix} - #{m.user.nick} has joined #{channel}."
    send_relay(message, channel)
  end

  private

  attr_reader :relay_channels

  def network_prefix
    Format(:bold, "[#{@bot.irc.network.name}]")
  end

  def from_self?(user)
    user.nick == @bot.nick
  end

  def format_message(message)
    if message.action?
      "#{network_prefix} * #{message.user.nick} #{message.action_message}"
    else
      "#{network_prefix} <#{message.user.nick}> #{message.message}"
    end
  end

  def send_relay(message, channel)
    target_channel = channel || default_channel
    return if target_channel.nil? || message.to_s.strip.empty?

    $bots.each_value do |bot|
      next if bot == @bot
      next unless ready_to_relay?(bot)

      bot.irc.send("PRIVMSG #{target_channel} :#{message}")
    rescue => e
      @bot.loggers.error("RelayPlugin failed to relay message: #{e.message}")
    end
  end

  def ready_to_relay?(bot)
    bot.irc && bot.irc.connected? && bot.irc.network != @bot.irc.network
  end

  def relay_channel?(channel)
    return false if channel.nil?
    @normalized_channels.include?(channel.downcase)
  end

  def channel_name(channel)
    return unless channel
    channel.respond_to?(:name) ? channel.name : channel.to_s
  end

  def default_channel
    relay_channels.first
  end

  def normalize_channels(channels)
    Array(channels).compact.map(&:to_s).reject(&:empty?).map do |channel|
      channel.start_with?('#') ? channel : "##{channel}"
    end.uniq
  end
end
