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

  def self.request_waiting(to_addr, r)
    msgstr = <<-END_OF_MESSAGE
      From: bnc.im bot <no-reply@bnc.im>
      To: #{to_addr}
      Reply-to: admin@bnc.im
      Subject: bnc.im account request - ##{r.id} for #{r.username}
      Date: #{Time.now.ctime}
      Message-Id: <#{UUID.generate}@bnc.im>

      There is a bnc.im account waiting to be approved. Details:

      ID: #{r.id}
      Username: #{r.username}
      Source: #{r.source} on #{r.ircnet}
      Server: #{r.server} #{r.port}
      Email: #{r.email}
      Timestamp: #{Time.at(r.ts).ctime}
      Requested server: #{r.reqserver || "not specified"}

      Regards,
      bnc.im bot
    END_OF_MESSAGE

    msg = msgstr.lines.map { |l| l.strip }.join("\r\n")

    self.send(to_addr, msg)
  end

  def self.send_approved(to_addr, server, user, pass)
    addr = $config["zncservers"][server]["addr"]
    webpanel = $config["zncservers"][server]["public"]["panel"]
    port = $config["zncservers"][server]["public"]["port"]
    sslport = $config["zncservers"][server]["public"]["sslport"]
    
    msgstr = <<-END_OF_MESSAGE
      From: bnc.im bot <no-reply@bnc.im>
      To: #{to_addr}
      Reply-to: admin@bnc.im
      Subject: bnc.im account approved
      Date: #{Time.now.ctime}
      Message-Id: <#{UUID.generate}@bnc.im>
      
      Dear #{user},
      
      Your bnc.im account has been approved. Your account details are:
      
      Server: #{addr}
      Server name: #{server}
      Plaintext Port: #{port}
      SSL Port: #{sslport}
      Username: #{user}
      Password: #{pass}
      Web Panel: #{webpanel}
      
      In order to connect to your new account, you will need to connect
      your IRC client to #{addr} on port #{port} (or #{sslport} for SSL) 
      and configure your client to send your bnc.im username and password 
      together in the server password field, seperated by a colon,
      like so: 
      
      #{user}:#{pass}
      
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
