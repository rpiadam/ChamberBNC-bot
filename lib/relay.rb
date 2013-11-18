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
  
  match /.*/, method: :relay, use_prefix: false
  
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
  
  def send_relay(m)
    $bots.each do |network, bot|
      unless bot.irc.network == @bot.irc.network
        bot.irc.send("PRIVMSG #bnc.im :#{m}")
      end
    end
  end
end
