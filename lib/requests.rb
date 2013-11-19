####
## bnc.im administration bot
## request lib
##
## Copyright (c) 2013 Andrew Northall
##
## MIT License
## See LICENSE file for details.
####

require 'cinch'
require 'domainatrix'
require 'csv'

class RequestDB
  @@requests = Hash.new

  def self.load(file)
    unless File.exists?(file)
      puts "Error: request db #{file} does not exist. Skipping loading."
      return
    end
    
    CSV.foreach(file) do |row|
      request = Request.new(row[0].to_i, row[3], row[7], row[4], \
                           row[5], row[6], row[1].to_i)
      request.key = row[2]
      request.approved = true if row[8] == "true"
      request.approved = false if row[8] == "false"
      request.confirmed = true if row[9] == "true"
      request.confirmed = false if row[9] == "false"
      request.ircnet = row[10]
      request.reqserver = row[11]
      @@requests[request.id] = request
    end
  end

  def self.save(file)
    file = File.open(file, 'w')
    csv_string = CSV.generate do |csv|
      @@requests.each_value do |r|
        csv << [r.id, r.ts, r.key, r.source, r.email, r.server, \
          r.port, r.username, r.approved?, r.confirmed?, r.ircnet,\
          r.reqserver]
      end
    end
    file.write csv_string
    file.close
  end

  def self.requests
    @@requests
  end

  def self.email_used?(email)
    @@requests.each_value do |request|
      if request.email.downcase == email.downcase
        return true
      else
        next
      end
    end
    return false
  end

  def self.username_used?(user)
    @@requests.each_value do |request|
      if request.username.downcase == user.downcase
        return true
      else
        next
      end
    end
    return false
  end

  def self.create(*args)
    obj = Request.new(self.next_id, *args)
    @@requests[obj.id] = obj
    RequestDB.save($config["requestdb"])
    @@requests[obj.id]
  end

  def self.next_id
    return 1 if @@requests.empty?
    max_id_request = @@requests.max_by { |k, v| k }
    max_id_request[0] + 1
  end

  def self.gen_key(length = 10)
    ([nil]*length).map { ((48..57).to_a+(65..90).to_a+(97..122).to_a).sample.chr }.join
  end

  def self.confirm(id, confirmed = true)
    @@requests[id].confirmed = confirmed
    RequestDB.save($config["requestdb"])
  end

  def self.approve(id, approved = true)
    @@requests[id].approved = approved
    RequestDB.save($config["requestdb"])
  end
  
  def self.set_requested_server(id, value)
    @@requests[id].reqserver = value
    RequestDB.save($config["requestdb"])
  end

  def self.delete_id(id)
    @@requests.delete id
    RequestDB.save($config["requestdb"])
  end
end

class Request
  attr_reader :id, :username
  attr_accessor :key, :ts, :approved, :confirmed
  attr_accessor :source, :email, :server, :port
  attr_accessor :ircnet, :reqserver

  def initialize(id, source, username, email, server, port, ircnet, ts = nil)
    @id = id
    @ts = ts || Time.now.to_i
    @key = RequestDB.gen_key(20)
    @approved = false
    @confirmed = false
    @source = source
    @username = username
    @ircnet = ircnet
    @email = email
    @server = server
    @port = port
    @reqserver = nil
  end

  def approved?
    @approved
  end

  def confirmed?
    @confirmed
  end
end

class RequestPlugin
  include Cinch::Plugin
  match /request\s+(\w+)\s+(\S+)\s+(\S+)\s+(\+?\d+)$/, method: :request, group: :request
  match /request\s+(\w+)\s+(\S+)\s+(\S+)\s+(\+?\d+)\s+(\w+)$/, method: :request, group: :request
  match /request/, method: :help, group: :request
  match "networks", method: :servers
  match "web", method: :web
  match "setup", method: :setup

  match /verify\s+(\d+)\s+(\S+)/, method: :verify
  
  match /topic (.+)/, method: :topic
  match /approve\s+(\d+)\s+(\S+)/, method: :approve
  match /delete\s+(\d+)/, method: :delete
  match /reqinfo\s+(\d+)/, method: :reqinfo
  match "pending", method: :pending
  match /fverify\s+(\d+)/, method: :fverify
  match /servers/, method: :servers
  match /broadcast (.+)/, method: :broadcast
  
  match "help", method: :help
  
  def request(m, username, email, server, port, reqserver = nil)
    if RequestDB.email_used?(email)
      m.reply "Sorry, that email has already been used. Please contact an " + \
              "operator if you need help."
      return
    elsif RequestDB.username_used?(username)
      m.reply "Error: that username has already been used. Please try another, or " + \
              "contact an operator for help."
      return
    end
    
    unless reqserver.nil?
      unless $config["zncservers"].keys.include? reqserver.downcase
        m.reply "Error: #{reqserver} is not a valid bnc.im server. " + \
                "Please pick from: #{$config["zncservers"].keys.join(", ")}"
        return
      end
    end
    
    r = RequestDB.create(m.user.mask, username, email, server,\
                         port, @bot.irc.network.name)
                         
    RequestDB.set_requested_server(r.id, reqserver) unless reqserver.nil?

    Mail.send_verify(r.email, r.id, r.key)
                               
    m.reply "Your request has been submitted. Please check your " + \
            "email for information on how to proceed."
  end

  def verify(m, id, key)
    unless RequestDB.requests.has_key?(id.to_i)
      m.reply "Error: request ##{id} not found. Please contact an operator if you need assistance."
      return
    end
    
    r = RequestDB.requests[id.to_i]
    
    unless r.key == key
      m.reply "Error: code does not match. Please contact an operator for assistance."
      return
    end

    if r.confirmed?
      m.reply "Error: request already confirmed."
      return
    end

    RequestDB.confirm(r.id)
    r = RequestDB.requests[r.id]

    m.reply "Request confirmed! Your request is now pending administrative approval. " + \
      "You will receive an email with further details when it is approved. Thanks for using bnc.im."

    $config["notifymail"].each do |email|
      Mail.request_waiting(email, r)
    end
    adminmsg("#{Format(:red, "[NEW REQUEST]")} #{format_status(r)}")
  end
  
  def topic(m, topic)
    return unless m.channel == "#bnc.im-admin"
    command = "TOPIC"
    if topic.split(" ")[0] == "--append"
      command = "TOPICAPPEND"
      topic = topic.split(" ")[1..-1].join(" ")
    elsif topic.split(" ")[0] == "--prepend"
      command = "TOPICPREPEND"
      topic = topic.split(" ")[1..-1].join(" ")
    end
    $bots.each_value do |bot|
      bot.irc.send("PRIVMSG ChanServ :#{command} #bnc.im #{topic}")
    end
    m.reply "done!"
  end
  
  def broadcast(m, text)
    return unless m.channel == "#bnc.im-admin"
    $bots.each_value do |bot|
      bot.irc.send("PRIVMSG #bnc.im :#{Format(:bold, "[BROADCAST]")} #{text}")
    end
    
    $zncs.each_value do |zncbot|
      zncbot.irc.send("PRIVMSG *status :broadcast [Broadcast Message] #{text}")
    end
    m.reply "done!"
  end
  
  def approve(m, id, ip)
    return unless m.channel == "#bnc.im-admin"
    unless RequestDB.requests.has_key?(id.to_i)
      m.reply "Error: request ##{id} not found."
      return
    end
    
    r = RequestDB.requests[id.to_i]
    
    unless r.confirmed?
      m.reply "Error: request ##{id} has not been confirmed by email."
      return
    end
    
    if r.approved?
      m.reply "Error: request ##{id} is already approved."
      return
    end
    
    server = find_server_by_ip(ip)
    
    if server.nil?
      m.reply "Error: #{ip} is not a valid IP address."
      return
    end
    
    password = RequestDB.gen_key(15)
    netname = Domainatrix.parse(r.server).domain
    
    $zncs[server].irc.send(msg_to_control("CloneUser templateuser #{r.username}"))
    $zncs[server].irc.send(msg_to_control("Set Nick #{r.username} #{r.username}"))
    $zncs[server].irc.send(msg_to_control("Set AltNick #{r.username} #{r.username}_"))
    $zncs[server].irc.send(msg_to_control("Set Ident #{r.username} #{r.username}"))
    $zncs[server].irc.send(msg_to_control("Set BindHost #{r.username} #{ip}"))
    $zncs[server].irc.send(msg_to_control("Set DCCBindHost #{r.username} #{ip}"))
    $zncs[server].irc.send(msg_to_control("Set DenySetBindHost #{r.username} true"))
    $zncs[server].irc.send(msg_to_control("Set Password #{r.username} #{password}"))
    
    Thread.new do
      sleep 3
      $zncs[server].irc.send(msg_to_control("AddNetwork #{r.username} #{netname}"))
      $zncs[server].irc.send(msg_to_control("SetNetwork Nick #{r.username} #{netname} #{r.username}"))
      $zncs[server].irc.send(msg_to_control("AddServer #{r.username} #{netname} #{r.server} #{r.port}"))
    end
    
    Mail.send_approved(r.email, server, r.username, password)
    RequestDB.approve(r.id)
    allmsg("#{r.source.to_s.split("!")[0]}: your request ##{r.id} has been approved :)")
    adminmsg("Request ##{id} approved to #{server} (#{ip}) by #{m.user}.")
  end
  
  def msg_to_control(msg)
    "PRIVMSG *controlpanel :#{msg}"
  end
  
  def find_server_by_ip(ip)
    ips = $config["ips"]
    ips.each do |server, addrs|
      addrs.each_value do |addr|
        addr.each do |a|
          if a.downcase == ip.downcase
            return server
          end
        end
      end
    end
    return false
  end
  
  def servers(m)
    if m.channel == "#bnc.im-admin"
      ips = $config["ips"]
      ips.each do |name, addrs|
        ipv4 = addrs["ipv4"]
        ipv6 = addrs["ipv6"]
        m.reply "#{Format(:bold, "[#{name}]")} #{Format(:bold, "IPv4:")} " + \
                "#{ipv4.join(", ")}. #{Format(:bold, "IPv6:")} #{ipv6.join(", ")}."
      end
    else
      m.reply "I am connected to the following IRC servers: #{$config["servers"].keys[0..-2].join(", ")} and #{$config["servers"].keys[-1]}."
      m.reply "I am connected to the following bnc.im servers: #{$config["zncservers"].keys[0..-2].join(", ")} and #{$config["zncservers"].keys[-1]}."
    end
  end
  
  def fverify(m, id)
    return unless m.channel == "#bnc.im-admin"
    unless RequestDB.requests.has_key?(id.to_i)
      m.reply "Error: request ##{id} not found."
      return
    end
    
    r = RequestDB.requests[id.to_i]
    
    if r.confirmed?
      m.reply "Error: request already confirmed."
      return
    end
    
    RequestDB.confirm(r.id)
    r = RequestDB.requests[id.to_i]
    
    adminmsg("Request ##{id} email verified by #{m.user}.")
    adminmsg("#{Format(:red, "[NEW REQUEST]")} #{format_status(r)}")
  end
  
  def reqinfo(m, id)
    return unless m.channel == "#bnc.im-admin"
    unless RequestDB.requests.has_key?(id.to_i)
      m.reply "Error: request ##{id} not found."
      return
    end
    
    r = RequestDB.requests[id.to_i]
    
    if r.nil?
      m.reply "Request ##{id} not found."
      return
    end
    
    m.reply format_status(r)
  end
  
  def delete(m, id)
    return unless m.channel == "#bnc.im-admin"
    unless RequestDB.requests.has_key?(id.to_i)
      m.reply "Error: request ##{id} not found."
      return
    end
    
    RequestDB.delete_id id.to_i
    m.reply "Deleted request ##{id}."
  end

  def allmsg(m)
    $bots.each do |network, bot|
      bot.irc.send("PRIVMSG #bnc.im :#{m}")
    end
  end
  
  def pending(m)
    return unless m.channel == "#bnc.im-admin"
    
    pending = Array.new
    RequestDB.requests.each_value do |r|
      pending << r unless r.approved?
    end
    
    if pending.empty?
      m.reply "No pending requests. Woop-de-fucking-do."
      return
    end
    
    m.reply "#{pending.size} pending request(s):"
    
    pending.each do |request|
      m.reply format_status(request)
    end
  end
  
  def help(m)
    if m.channel == "#bnc.im-admin"
      m.reply "Admin commands:"
      m.reply "!pending | !reqinfo <id> | !delete <id> | !fverify <id> | !servers | !approve <id> <ip>"
      return
    end
    m.reply "#{Format(:bold, "Syntax: !request <user> <email> <server> [+]<port> [bnc.im server]")}. Parameters in brackets are not required. A + before the port denotes SSL. This command can be issued in a private message."
    m.reply "For example, a user called bncim-lover with an email of ilovebncs@mail.com who wants a bouncer for Interlinked on our chicago server would issue: " + \
             Format(:bold, "!request bncim-lover ilovebncs@mail.com irc.interlinked.me 6667 chicago")
  end

  def web(m)
    m.reply "http://bnc.im"
  end

  def setup(m)
    m.reply "http://bnc.im/setup.html"
  end

  def adminmsg(text)
    $adminbot.irc.send("PRIVMSG #bnc.im-admin :#{text}")
  end
  
  def format_status(r)
    "%s Source: %s on %s / Email: %s / Date: %s / Server: %s / Port: %s / Requested Server: %s / Confirmed: %s / Approved: %s" %
      [Format(:bold, "[##{r.id}]"), Format(:bold, r.source.to_s), 
       Format(:bold, r.ircnet.to_s), Format(:bold, r.email.to_s),
       Format(:bold, Time.at(r.ts).ctime), Format(:bold, r.server),
       Format(:bold, r.port.to_s), Format(:bold, "#{r.reqserver || "N/A"}"),
       Format(:bold, r.confirmed?.to_s), Format(:bold, r.approved?.to_s)]
  end
end
