# Version 1.0.12
#
# Webhook parameters in NowSMS : /?SmsMessageSid=@@FULLSMS@@&AccountSid=sms&From=@@SENDER@@&To=@@RECIP@@&Body=@@FULLSMS@@&IgnoreRegexp=...
#
# NowSMS documentation : https://www.nowsms.com/doc/2-way-sms-support
#
# Based on app/models/channel/driver/sms/twilio.rb
# Inspired by https://github.com/lcx/zammad-sms-cloudvox
#
# In order to make an installable package, this file need to
# be base64 encoded inside nowsms-sms.szpm
# (by using for example https://base64.guru/converter/encode/text)
#
# Copyright (c) 2021-2023 SysCo systemes de communication sa - https://www.sysco.ch

class Channel::Driver::Sms::Nowsms
  NAME = 'sms/nowsms'.freeze

  def fetchable?(_channel)
    false
  end

  def send(options, attr, _notification = false)
    Rails.logger.info "Sending SMS to #{attr[:recipient]}"

    return true if Setting.get('import_mode')

    Rails.logger.info "Backend sending NowSMS SMS to #{attr[:recipient]}"
    begin
      if Setting.get('developer_mode') != true
        conn = Faraday.new(url: options[:gateway])
        response = conn.get("/", { :User => options[:account_id], :Password => options[:token], :PhoneNumber => attr[:recipient].remove(/\D/), :Text => attr[:message]})
        raise response.body if !response.body.match?('Message Submitted')
      end

      true
    rescue => e
      Rails.logger.debug "NowSMS error: #{e.inspect}"
      raise e
    end
  end

  def process(_options, attr, channel)
    Rails.logger.info "Receiving SMS from recipient #{attr[:From]}"

    # reject specific contents
    if _options[:reject_msg].present?
      pattern = Regexp.new(_options[:reject_msg]).freeze
      if pattern.match?(attr[:Body])
        return ['application/json; charset=UTF-8;', { status: 'rejected', reason: 'content', ticket_id: ''}.to_json]
      end
    end

    # reject specific senders
    if _options[:reject_sender].present?
      pattern = Regexp.new(_options[:reject_sender]).freeze
      if pattern.match?(attr[:Body])
        return ['application/json; charset=UTF-8;', { status: 'rejected', reason: 'sender', ticket_id: ''}.to_json]
      end
    end

    # prevent already created articles
    if Ticket::Article.find_by(message_id: attr[:SmsMessageSid])
      return ['application/json; charset=UTF-8;', { status: 'processed', reason: 'duplicate', ticket_id: ''}.to_json]
    end

    # find sender
    user = User.where(mobile: attr[:From]).order(:updated_at).first
    if !user
      _from_comment, preferences = Cti::CallerId.get_comment_preferences(attr[:From], 'from')
      if preferences && preferences['from'] && preferences['from'][0]
        if preferences['from'][0]['level'] == 'known' && preferences['from'][0]['object'] == 'User'
          user = User.find_by(id: preferences['from'][0]['o_id'])
        end
      end
    end
    if !user
      user = User.create!(
        firstname: attr[:From],
        mobile:    attr[:From],
      )
    end

    UserInfo.current_user_id = user.id

    # find ticket
    article_type_sms = Ticket::Article::Type.find_by(name: 'sms')
    state_ids = Ticket::State.where(name: %w[closed merged removed]).pluck(:id)
    ticket = Ticket.where(customer_id: user.id, create_article_type_id: article_type_sms.id).where.not(state_id: state_ids).order(:updated_at).first
    ticket_action = 'created'

    if ticket
      ticket_action = 'updated'
      new_state = Ticket::State.find_by(default_create: true)
      if ticket.state_id != new_state.id
        ticket.state = Ticket::State.find_by(default_follow_up: true)
        ticket.save!
      end
    else
      if channel.group_id.blank?
        raise Exceptions::UnprocessableEntity, 'Group needed in channel definition!'
      end

      group = Group.find_by(id: channel.group_id)
      if !group
        raise Exceptions::UnprocessableEntity, 'Group is invalid!'
      end

      title = attr[:Body]
      if title.length > 40
        title = "#{title[0, 40]}..."
      end
      ticket = Ticket.new(
        group_id:    channel.group_id,
        title:       title,
        state_id:    Ticket::State.find_by(default_create: true).id,
        priority_id: Ticket::Priority.find_by(default_create: true).id,
        customer_id: user.id,
        preferences: {
          channel_id: channel.id,
          sms:        {
            AccountSid: attr['AccountSid'],
            From:       attr['From'],
            To:         attr['To'],
          }
        }
      )
      ticket.save!
    end

    Ticket::Article.create!(
      ticket_id:    ticket.id,
      type:         article_type_sms,
      sender:       Ticket::Article::Sender.find_by(name: 'Customer'),
      body:         attr[:Body],
      from:         attr[:From],
      to:           attr[:To],
      message_id:   attr[:SmsMessageSid],
      content_type: 'text/plain',
      preferences:  {
        channel_id: channel.id,
        sms:        {
          AccountSid: attr['AccountSid'],
          From:       attr['From'],
          To:         attr['To'],
        }
      }
    )

    ['application/json; charset=UTF-8;', { status: ticket_action, ticket_id: ticket.id }.to_json]
  end

  def self.definition
    {
      name:         'nowsms',
      adapter:      'sms/nowsms',
      account:      [
        { name: 'options::gateway', display: 'Gateway URL', tag: 'input', type: 'text', limit: 200, null: false, placeholder: 'http://server.ip.addr:8800' },
        { name: 'options::webhook_token', display: 'Webhook Token', tag: 'input', type: 'text', limit: 200, null: false, default: Digest::MD5.hexdigest(rand(999_999_999_999).to_s), disabled: true, readonly: true },
        { name: 'options::account_id', display: 'NowSMS username', tag: 'input', type: 'text', limit: 200, null: false, placeholder: 'XXXXXX' },
        { name: 'options::token', display: 'NowSMS password', tag: 'input', type: 'text', limit: 200, null: false },
        { name: 'options::sender', display: 'Sender', tag: 'input', type: 'text', limit: 200, null: false, placeholder: '+41790000000' },
        { name: 'options::reject_msg', display: 'Reject messages (regexp)', tag: 'input', type: 'text', limit: 200, null: false, placeholder: '.*loop_check.*|.*test_only.*' },
        { name: 'options::reject_sender', display: 'Reject senders (regexp)', tag: 'input', type: 'text', limit: 200, null: false, placeholder: 'spam_number|\+4199.*' },
        { name: 'group_id', display: 'Destination Group', tag: 'select', null: false, relation: 'Group', nulloption: true, filter: { active: true } },
      ],
      notification: [
        { name: 'options::gateway', display: 'Gateway URL', tag: 'input', type: 'text', limit: 200, null: false, placeholder: 'http://server.ip.addr:8800' },
        { name: 'options::account_id', display: 'NowSMS username', tag: 'input', type: 'text', limit: 200, null: false, placeholder: 'XXXXXX' },
        { name: 'options::token', display: 'NowSMS password', tag: 'input', type: 'text', limit: 200, null: false },
        { name: 'options::sender', display: 'Sender', tag: 'input', type: 'text', limit: 200, null: false, placeholder: '+41790000000' },
      ],
    }
  end

end
