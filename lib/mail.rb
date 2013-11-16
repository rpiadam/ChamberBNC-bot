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
    
    msgstr = <<END_OF_MESSAGE
From: bnc.im bot <no-reply@bnc.im>
To: #{to_addr}
Subject: bnc.im account verification
Date: #{Time.now.ctime}
Message-Id: <#{UUID.generate}@bnc.im>

Someone, hopefully you, requested an account in the http://bnc.im IRC channel. If this was you, please send

  !verify #{id} #{code} 

in either #bnc.im or in a private message to the bot. If you need any help, please visit http://bnc.im/webchat.html.

Regards,
bnc.im team
END_OF_MESSAGE

    self.send(to_addr, msgstr)
  end
end
