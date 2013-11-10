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
		CSV.foreach(file) do |row|
			request = Request.new(row[0].to_i, row[3], row[4], row[5], \
													 row[6], row[1].to_i)
			request.key = row[2]
			request.approved = row[7]
			request.confirmed = row[8]
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
					r.port, r.approved?, r.confirmed?]
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
	end

	def self.next_id
		max_id_request = @@requests.max_by { |k, v| k }
		max_id_request[0] + 1
	end

	def self.gen_key(length = 10)
		([nil]*length).map { ((48..57).to_a+(65..90).to_a+(97..122).to_a).sample.chr }.join
	end

	def self.confirm(id, confirmed = true)
		@@requests[id].confirmed = confirmed
	end

	def self.approve(id, approved = true)
		@@requests[id].approved = approved
	end
end

class Request
	attr_reader :id
	attr_accessor :key, :ts, :approved, :confirmed
	attr_accessor :source, :email, :server, :port

	def initialize(id, source, email, server, port, ts = nil)
		@id = id
		@ts = ts || Time.now.to_i
		@key = RequestDB.gen_key(15)
		@approved = false
		@confirmed = false
		@source = source
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

