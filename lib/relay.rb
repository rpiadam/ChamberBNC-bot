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
  
  match //, method: :relay
  
  def relay(m)
    network = Format(:bold, "[#{@bot.irc.network}]")
    message = "#{network} <#{m.user.nick}> #{m.message}"
    send_relay(message)
  end
  
  def send_relay(m)
    $bots.each do |network, bot|
      unless bot == @bot
        bot.irc.send("PRIVMSG #bnc.im :#{m}")
      end
    end
  end
end