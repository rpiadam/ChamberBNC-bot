####
## chamberBNC administration bot
## ticket system
##
## Copyright (c) 2022 Andrew Northall
##
## MIT License
## See LICENSE file for details.
####

require 'cinch'
require 'csv'
require 'time'

class TicketDB
  @@tickets = {}
  @@mutex = Mutex.new

  TICKET_STATUSES = %w[open in-progress closed resolved].freeze

  def self.load(file)
    return unless File.exist?(file)

    @@mutex.synchronize do
      CSV.foreach(file, headers: true) do |row|
        ticket = Ticket.new(
          row['id'].to_i,
          row['creator'],
          row['subject'],
          row['message'],
          row['status'],
          row['assigned_to'] || '',
          row['created_at'].to_i,
          row['updated_at'].to_i,
          row['network'] || ''
        )
        ticket.replies = parse_replies(row['replies'] || '')
        @@tickets[ticket.id] = ticket
      end
    end
  rescue => e
    warn "Failed to load ticket database: #{e.message}"
  end

  def self.save(file)
    @@mutex.synchronize do
      CSV.open(file, 'w', write_headers: true, headers: %w[id creator subject message status assigned_to created_at updated_at network replies]) do |csv|
        @@tickets.each_value do |ticket|
          csv << [
            ticket.id,
            ticket.creator,
            ticket.subject,
            ticket.message,
            ticket.status,
            ticket.assigned_to || '',
            ticket.created_at,
            ticket.updated_at,
            ticket.network,
            serialize_replies(ticket.replies)
          ]
        end
      end
    end
  rescue => e
    warn "Failed to save ticket database: #{e.message}"
  end

  def self.tickets
    @@tickets
  end

  def self.create(creator, subject, message, network = '')
    id = next_id
    ticket = Ticket.new(id, creator, subject, message, 'open', '', Time.now.to_i, Time.now.to_i, network)
    @@tickets[id] = ticket
    save($config['ticketdb'])
    ticket
  end

  def self.find(id)
    @@tickets[id.to_i]
  end

  def self.find_by_creator(creator_mask)
    @@tickets.values.select { |t| t.creator.downcase == creator_mask.downcase }
  end

  def self.open_tickets
    @@tickets.values.select { |t| %w[open in-progress].include?(t.status) }
  end

  def self.next_id
    return 1 if @@tickets.empty?
    @@tickets.keys.max + 1
  end

  def self.update_status(id, status, assigned_to = nil)
    ticket = find(id)
    return nil unless ticket

    ticket.status = status
    ticket.assigned_to = assigned_to if assigned_to
    ticket.updated_at = Time.now.to_i
    save($config['ticketdb'])
    ticket
  end

  def self.add_reply(id, author, message)
    ticket = find(id)
    return nil unless ticket

    reply = TicketReply.new(author, message, Time.now.to_i)
    ticket.replies << reply
    ticket.updated_at = Time.now.to_i
    save($config['ticketdb'])
    ticket
  end

  private

  def self.parse_replies(replies_str)
    return [] if replies_str.nil? || replies_str.empty?

    replies_str.split('|||').map do |reply_str|
      parts = reply_str.split(':::', 3)
      next nil if parts.size != 3

      TicketReply.new(parts[0], parts[1], parts[2].to_i)
    end.compact
  end

  def self.serialize_replies(replies)
    replies.map { |r| "#{r.author}:::#{r.message}:::#{r.timestamp}" }.join('|||')
  end
end

class Ticket
  attr_reader :id, :creator, :subject, :message, :created_at, :updated_at, :network
  attr_accessor :status, :assigned_to, :replies

  def initialize(id, creator, subject, message, status, assigned_to, created_at, updated_at, network)
    @id = id
    @creator = creator
    @subject = subject
    @message = message
    @status = status
    @assigned_to = assigned_to || ''
    @created_at = created_at
    @updated_at = updated_at
    @network = network
    @replies = []
  end

  def open?
    status == 'open'
  end

  def closed?
    %w[closed resolved].include?(status)
  end

  def created_time
    Time.at(@created_at)
  end

  def updated_time
    Time.at(@updated_at)
  end
end

class TicketReply
  attr_reader :author, :message, :timestamp

  def initialize(author, message, timestamp)
    @author = author
    @message = message
    @timestamp = timestamp
  end

  def time
    Time.at(@timestamp)
  end
end

class TicketAudit
  LOG_PATH = File.expand_path('../log/ticket-events.log', __dir__)

  def self.log(event, metadata = {})
    line = "[#{Time.now.utc.iso8601}] #{event}"
    unless metadata.empty?
      details = metadata.map { |k, v| "#{k}=#{sanitize(v)}" }.join(' ')
      line += " #{details}"
    end

    mutex.synchronize do
      File.open(LOG_PATH, 'a') { |f| f.puts(line) }
    end
  rescue => e
    warn "TicketAudit logging failed: #{e.message}"
  end

  def self.mutex
    @mutex ||= Mutex.new
  end
  private_class_method :mutex

  def self.sanitize(value)
    value.to_s.gsub(/\s+/, '_')
  end
  private_class_method :sanitize
end

class TicketPlugin
  include Cinch::Plugin

  match /ticket\s+new\s+(.+?)\s+::\s+(.+)$/i, method: :create_ticket
  match /ticket\s+(\d+)$/i, method: :view_ticket
  match /ticket\s+reply\s+(\d+)\s+(.+)$/i, method: :reply_ticket
  match /tickets$/i, method: :list_user_tickets
  match /ticket\s+help$/i, method: :ticket_help

  # Admin commands
  match /ticketlist$/i, method: :list_all_tickets
  match /ticketinfo\s+(\d+)$/i, method: :ticket_info
  match /ticketclose\s+(\d+)$/i, method: :close_ticket
  match /ticketresolve\s+(\d+)$/i, method: :resolve_ticket
  match /ticketreopen\s+(\d+)$/i, method: :reopen_ticket
  match /ticketassign\s+(\d+)\s+(.+)$/i, method: :assign_ticket
  match /ticketstatus\s+(\d+)\s+(.+)$/i, method: :set_status

  def create_ticket(m, subject, message)
    if subject.length > 100
      m.reply "Error: Subject is too long (maximum 100 characters)."
      return
    end

    if message.length > 1000
      m.reply "Error: Message is too long (maximum 1000 characters)."
      return
    end

    ticket = TicketDB.create(m.user.mask, subject.strip, message.strip, @bot.irc.network.name)

    m.reply "Support ticket ##{ticket.id} created successfully. " \
            "You can view it with: !ticket #{ticket.id}"

    adminmsg("#{Format(:green, '[NEW TICKET]')} ##{ticket.id} - #{subject.strip} " \
             "from #{m.user.nick} (#{m.user.mask})")

    notify_admins_new_ticket(ticket)
    TicketAudit.log('ticket_created', id: ticket.id, user: m.user.nick, mask: m.user.mask)
  end

  def view_ticket(m, id)
    ticket = TicketDB.find(id.to_i)
    unless ticket
      m.reply "Error: Ticket ##{id} not found."
      return
    end

    unless can_view_ticket?(m, ticket)
      m.reply "Error: You don't have permission to view this ticket."
      return
    end

    status_color = status_color_for(ticket.status)
    m.reply "#{Format(:bold, "Ticket ##{ticket.id}")}: #{Format(status_color, ticket.status.upcase)} - #{ticket.subject}"
    m.reply "Created: #{ticket.created_time.strftime('%Y-%m-%d %H:%M:%S UTC')} by #{ticket.creator}"
    m.reply "Message: #{ticket.message}"

    if ticket.assigned_to && !ticket.assigned_to.empty?
      m.reply "Assigned to: #{Format(:bold, ticket.assigned_to)}"
    end

    if ticket.replies.any?
      m.reply "Replies (#{ticket.replies.size}):"
      ticket.replies.each_with_index do |reply, idx|
        m.reply "  [#{idx + 1}] #{reply.author} (#{reply.time.strftime('%Y-%m-%d %H:%M')}): #{reply.message}"
      end
    else
      m.reply "No replies yet."
    end
  end

  def reply_ticket(m, id, message)
    ticket = TicketDB.find(id.to_i)
    unless ticket
      m.reply "Error: Ticket ##{id} not found."
      return
    end

    unless can_view_ticket?(m, ticket)
      m.reply "Error: You don't have permission to reply to this ticket."
      return
    end

    if ticket.closed?
      m.reply "Error: Cannot reply to a closed ticket. Use !ticketreopen #{id} (admin only) to reopen it."
      return
    end

    TicketDB.add_reply(id.to_i, m.user.mask, message.strip)
    ticket = TicketDB.find(id.to_i)

    m.reply "Reply added to ticket ##{id}."

    if admin_channel?(m.channel)
      adminmsg("Ticket ##{id} replied to by #{m.user.nick}: #{message.strip}")
    else
      adminmsg("#{Format(:yellow, '[TICKET REPLY]')} ##{id} - #{m.user.nick} replied: #{message.strip}")
    end

    notify_ticket_update(ticket, m.user.nick, message.strip)
    TicketAudit.log('ticket_replied', id: id.to_i, user: m.user.nick, mask: m.user.mask)
  end

  def list_user_tickets(m)
    tickets = TicketDB.find_by_creator(m.user.mask)
    if tickets.empty?
      m.reply "You have no support tickets. Create one with: !ticket new <subject> :: <message>"
      return
    end

    m.reply "Your tickets (#{tickets.size}):"
    tickets.sort_by(&:created_at).reverse.each do |ticket|
      status_color = status_color_for(ticket.status)
      m.reply "  ##{ticket.id} - #{Format(status_color, ticket.status.upcase)} - #{ticket.subject} " \
              "(#{ticket.created_time.strftime('%Y-%m-%d')})"
    end
  end

  def list_all_tickets(m)
    return unless admin_channel?(m.channel)

    open_tickets = TicketDB.open_tickets
    if open_tickets.empty?
      m.reply "No open tickets."
      return
    end

    m.reply "Open tickets (#{open_tickets.size}):"
    open_tickets.sort_by(&:created_at).each do |ticket|
      status_color = status_color_for(ticket.status)
      assigned = ticket.assigned_to && !ticket.assigned_to.empty? ? " (assigned: #{ticket.assigned_to})" : ''
      m.reply "  ##{ticket.id} - #{Format(status_color, ticket.status.upcase)} - #{ticket.subject}#{assigned} " \
              "by #{ticket.creator.split('!').first} (#{ticket.created_time.strftime('%Y-%m-%d')})"
    end
  end

  def ticket_info(m, id)
    return unless admin_channel?(m.channel)

    ticket = TicketDB.find(id.to_i)
    unless ticket
      m.reply "Error: Ticket ##{id} not found."
      return
    end

    status_color = status_color_for(ticket.status)
    m.reply "#{Format(:bold, "Ticket ##{ticket.id}")}: #{Format(status_color, ticket.status.upcase)}"
    m.reply "Subject: #{ticket.subject}"
    m.reply "Creator: #{ticket.creator} on #{ticket.network}"
    m.reply "Created: #{ticket.created_time.strftime('%Y-%m-%d %H:%M:%S UTC')}"
    m.reply "Updated: #{ticket.updated_time.strftime('%Y-%m-%d %H:%M:%S UTC')}"
    m.reply "Assigned: #{ticket.assigned_to || 'Unassigned'}"
    m.reply "Message: #{ticket.message}"
    m.reply "Replies: #{ticket.replies.size}"
  end

  def close_ticket(m, id)
    return unless admin_channel?(m.channel)

    ticket = TicketDB.update_status(id.to_i, 'closed')
    unless ticket
      m.reply "Error: Ticket ##{id} not found."
      return
    end

    m.reply "Ticket ##{id} closed."
    adminmsg("Ticket ##{id} closed by #{m.user.nick}.")
    TicketAudit.log('ticket_closed', id: id.to_i, admin: m.user.nick)
  end

  def resolve_ticket(m, id)
    return unless admin_channel?(m.channel)

    ticket = TicketDB.update_status(id.to_i, 'resolved')
    unless ticket
      m.reply "Error: Ticket ##{id} not found."
      return
    end

    m.reply "Ticket ##{id} marked as resolved."
    adminmsg("Ticket ##{id} resolved by #{m.user.nick}.")
    TicketAudit.log('ticket_resolved', id: id.to_i, admin: m.user.nick)
  end

  def reopen_ticket(m, id)
    return unless admin_channel?(m.channel)

    ticket = TicketDB.update_status(id.to_i, 'open')
    unless ticket
      m.reply "Error: Ticket ##{id} not found."
      return
    end

    m.reply "Ticket ##{id} reopened."
    adminmsg("Ticket ##{id} reopened by #{m.user.nick}.")
    TicketAudit.log('ticket_reopened', id: id.to_i, admin: m.user.nick)
  end

  def assign_ticket(m, id, assignee)
    return unless admin_channel?(m.channel)

    ticket = TicketDB.update_status(id.to_i, 'in-progress', assignee.strip)
    unless ticket
      m.reply "Error: Ticket ##{id} not found."
      return
    end

    m.reply "Ticket ##{id} assigned to #{assignee.strip} and set to in-progress."
    adminmsg("Ticket ##{id} assigned to #{Format(:bold, assignee.strip)} by #{m.user.nick}.")
    TicketAudit.log('ticket_assigned', id: id.to_i, assignee: assignee.strip, admin: m.user.nick)
  end

  def set_status(m, id, status)
    return unless admin_channel?(m.channel)

    unless TicketDB::TICKET_STATUSES.include?(status.downcase)
      m.reply "Error: Invalid status. Valid statuses: #{TicketDB::TICKET_STATUSES.join(', ')}"
      return
    end

    ticket = TicketDB.update_status(id.to_i, status.downcase)
    unless ticket
      m.reply "Error: Ticket ##{id} not found."
      return
    end

    m.reply "Ticket ##{id} status set to #{status.downcase}."
    adminmsg("Ticket ##{id} status changed to #{Format(:bold, status.downcase)} by #{m.user.nick}.")
    TicketAudit.log('ticket_status_changed', id: id.to_i, status: status.downcase, admin: m.user.nick)
  end

  def ticket_help(m)
    if admin_channel?(m.channel)
      m.reply "Admin ticket commands:"
      m.reply "  !ticketlist - List all open tickets"
      m.reply "  !ticketinfo <id> - View detailed ticket information"
      m.reply "  !ticketassign <id> <admin> - Assign ticket to admin"
      m.reply "  !ticketclose <id> - Close a ticket"
      m.reply "  !ticketresolve <id> - Mark ticket as resolved"
      m.reply "  !ticketreopen <id> - Reopen a closed ticket"
      m.reply "  !ticketstatus <id> <status> - Set ticket status (open, in-progress, closed, resolved)"
    else
      m.reply "Support ticket commands:"
      m.reply "  !ticket new <subject> :: <message> - Create a new support ticket"
      m.reply "  !ticket <id> - View a ticket and its replies"
      m.reply "  !ticket reply <id> <message> - Reply to a ticket"
      m.reply "  !tickets - List all your tickets"
      m.reply "  !ticket help - Show this help"
    end
  end

  private

  def admin_channel?(channel)
    return false unless channel
    channel_name = channel.respond_to?(:name) ? channel.name : channel.to_s
    channel_name.downcase == $config['admin']['channel'].downcase
  end

  def can_view_ticket?(m, ticket)
    return true if admin_channel?(m.channel)
    ticket.creator.downcase == m.user.mask.downcase
  end

  def status_color_for(status)
    case status.downcase
    when 'open' then :yellow
    when 'in-progress' then :blue
    when 'closed' then :red
    when 'resolved' then :green
    else :white
    end
  end

  def adminmsg(text)
    return unless $adminbot
    $adminbot.irc.send("PRIVMSG #{$config['admin']['channel']} :#{text}")
  end

  def notify_admins_new_ticket(ticket)
    return unless $config['notifymail']

    $config['notifymail'].each do |email|
      Mail.ticket_created(email, ticket)
    end
  end

  def notify_ticket_update(ticket, replier, message)
    return unless $config['notifymail']

    $config['notifymail'].each do |email|
      Mail.ticket_updated(email, ticket, replier, message)
    end
  end
end

