####
### bnc.im administration bot
### mail lib
###
### Copyright (c) 2013 Andrew Northall
###
### MIT License
### See LICENSE file for details.
#####

require 'net/smtp'
require 'uuid'

class Mail
  def self.send(to_addr, message)
    conf = $config["mail"]
    Net::SMTP.start(conf["server"], conf["port"], 'bnc.im', conf["user"], \
                    conf["pass"], :plain) do |smtp|
      smtp.enable_starttls
      smtp.send_message message, 'no-reply@bnc.im',
        to_addr
    end
  end

  def self.send_verify(to_addr, id, code)
    
    msgstr = <<-END_OF_MESSAGE
      From: bnc.im bot <no-reply@bnc.im>
      To: #{to_addr}
      Reply-to: admin@bnc.im
      Subject: bnc.im account verification
      Date: #{Time.now.ctime}
      Message-Id: <#{UUID.generate}@bnc.im>

      Someone, hopefully you, requested an account in the http://bnc.im IRC channel. If this was you, please send

      !verify #{id} #{code} 

      in either #bnc.im or in a private message to the bot. If you need any help, please visit http://bnc.im/webchat.html.

      Regards,
      bnc.im team
			http://bnc.im/
    END_OF_MESSAGE
    
    # remove whitespace from above
    msg = msgstr.lines.map { |l| l.strip }.join("\r\n")

    self.send(to_addr, msg)
  end
  
  def self.send_approved(to_addr, server, addr, webpanel, user, pass)
    
    msgstr = <<-END_OF_MESSAGE
      From: bnc.im bot <no-reply@bnc.im>
      To: #{to_addr}
      Reply-to: admin@bnc.im
      Subject: bnc.im account approved
      Date: #{Time.now.ctime}
      Message-Id: <#{UUID.generate}@bnc.im>
      
      Dear #{user},
      
      Your bnc.im account has been approved. Your account details are:
      
      Server: #{server} (#{addr})
      Username: #{user}
      Password: #{pass}
      Web Panel: #{webpanel}
      
      In order to connect to your new account, you will need to connect
      your IRC client to #{addr} on port 6667 (or 6697 for SSL) and
      configure your IRC client to send your username and password 
      together in the server password field, seperated by a colon,
      like so:  #{user}:#{pass}
      
      If you need any help, please do not hestitate to join our IRC 
      channel: irc.interlinked.me #bnc.im - or connect to our webchat
      at https://bnc.im/webchat.html.
      
      Regards,
      bnc.im team
			http://bnc.im/
    END_OF_MESSAGE
    
    # remove whitespace from above
    msg = msgstr.lines.map { |l| l.strip }.join("\r\n")

    self.send(to_addr, msg)
  end
      
end
