####
## bnc.im administration bot
## request lib
##
## Copyright (c) 2013 Andrew Northall
##
## MIT License
## See LICENSE file for details.
####

class RelayPlugin
  include Cinch::Plugin
  
  listen_to :message, method: :relay
  listen_to :leaving, method: :relay_part
  listen_to :join, method: :relay_join
  
  
  def relay(m)
    return unless m.channel == "#bnc.im"
    network = Format(:bold, "[#{@bot.irc.network.name}]")
    if m.action?
      message = "#{network} * #{m.user.nick} #{m.action_message}"
    else
      message = "#{network} <#{m.user.nick}> #{m.message}"
    end
    send_relay(message)
  end
  
  def relay_part(m)
    return unless m.channel == "#bnc.im"
    network = Format(:bold, "[#{@bot.irc.network.name}]")
    message = "#{network} - #{m.user.nick} has left #bnc.im."
    send_relay(message)
  end
  
  def relay_join(m)
    return unless m.channel == "#bnc.im"
    network = Format(:bold, "[#{@bot.irc.network.name}]")
    message = "#{network} - #{m.user.nick} has joined #bnc.im."
    send_relay(message)
  end
  
  def send_relay(m)
    $bots.each do |network, bot|
      unless bot.irc.network == @bot.irc.network
        bot.irc.send("PRIVMSG #bnc.im :#{m}")
      end
    end
  end
end
