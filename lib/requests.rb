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
			request.approved = row[8]
			request.confirmed = row[9]
      request.ircnet = row[10]
			@@requests[request.id] = request
		end
		@@requests.each { |id, req| puts "Request #{id} loaded: " +  
			"#{req.inspect}" }
	end

	def self.save(file)
		file = File.open(file, 'w')
		csv_string = CSV.generate do |csv|
			@@requests.each_value do |r|
				csv << [r.id, r.ts, r.key, r.source, r.email, r.server, \
					r.port, r.username, r.approved?, r.confirmed?, r.ircnet]
			end
		end
		file.write csv_string
		file.close
	end

	def self.requests
		@@requests
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

	def self.delete_id(id)
		@@requests.delete id
		RequestDB.save($config["requestdb"])
	end
end

class Request
	attr_reader :id, :username
	attr_accessor :key, :ts, :approved, :confirmed
	attr_accessor :source, :email, :server, :port
  attr_accessor :ircnet

	def initialize(id, source, username, email, server, port, ircnet, ts = nil)
		@id = id
		@ts = ts || Time.now.to_i
		@key = RequestDB.gen_key(15)
		@approved = false
		@confirmed = false
		@source = source
		@username = username
    @ircnet = ircnet
		@email = email
		@server = server
		@port = port
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
	match /request\s+(\w+)\s+(\S+)\s+(\S+)\s+(\+?\d+)/, method: :request, group: :request
	match /request/, method: :help, group: :request
  
  match /delete\s+(\d+)/, method: :delete, group: :admin
  match /reqinfo\s+(\d+)/, method: :reqinfo, group: :admin

	def request(m, username, email, server, port)
		r = RequestDB.create(m.user.mask, username, email, \
															 server, port, @bot.irc.network.name)
                               
    reply = "%s %s Source: %s on %s / Date: %s / Server: %s / Port: %s / Approved: %s" % 
     [Format(:red, "[NEW REQUEST]"), Format(:bold, "[##{r.id}]"), 
      Format(:bold, r.source.to_s), Format(:bold, r.ircnet.to_s),
      Format(:bold, Time.at(r.ts).ctime), Format(:bold, r.server),
      Format(:bold, r.port.to_s), Format(:bold, r.approved?.to_s)]                         
    
    adminmsg reply
    m.reply "Your request has been submitted. Please check your " + \
            "email for information on how to proceed."
	end
  
  def reqinfo(m, id)
    return unless m.channel == "#bnc.im-admin"
    r = RequestDB.requests[id.to_i]
    
    if r.nil?
      m.reply "Request ##{id} not found."
      return
    end
    
    reply = "%s Source: %s on %s / Date: %s / Server: %s / Port: %s / Approved: %s" % 
      [Format(:bold, "[##{r.id}]"), Format(:bold, r.source.to_s), 
       Format(:bold, r.ircnet.to_s), Format(:bold, Time.at(r.ts).ctime), 
       Format(:bold, r.server), Format(:bold, r.port.to_s), 
       Format(:bold, r.approved?.to_s)]                         
    
    m.reply reply
  end
  
  def delete(m, id)
    return unless m.channel == "#bnc.im-admin"
    RequestDB.delete_id id.to_i
    m.reply "Deleted request ##{id}."
  end
  
  def help(m)
    m.reply "Invalid syntax. Syntax: !request <user> <email> <server> [+]<port>"
    m.reply "For example, a user called bncim-lover with an email of ilovebncs@mail.com who wants a bouncer for Interlinked would issue: !request bncim-lover ilovebncs@mail.com irc.interlinked.me 6667"
  end

	def adminmsg(text)
    $adminbot.irc.send("PRIVMSG #bnc.im-admin :#{text}")
	end
end
