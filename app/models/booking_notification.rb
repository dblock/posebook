# frozen_string_literal: true

class BookingNotification
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :booking, inverse_of: nil
  belongs_to :recipient, class_name: 'User', inverse_of: nil
  belongs_to :previous_booking, class_name: 'Booking', inverse_of: nil, optional: true
  field :kind, type: String
  field :event_key, type: String
  field :signature, type: String
  field :attendance_revision, type: Integer
  field :scheduled_for, type: Time
  field :previous_location, type: Hash
  field :state, type: String, default: 'pending'
  field :sent_at, type: Time
  field :expires_at, type: Time
  index({ event_key: 1, recipient_id: 1 }, unique: true)
  index({ state: 1, created_at: 1 })
  index({ booking_id: 1 })

  def self.coordinators(program)
    ids = ProgramMembership.coordinators.where(program_id: program.id).pluck(:user_id) +
          VenueMembership.coordinators.where(venue_id: program.venue_id).pluck(:user_id)
    User.active.where(:id.in => ids.uniq).to_a
  end

  def self.signature(booking)
    location = booking.program.venue
    Digest::SHA256.hexdigest(
      [booking.user_id, booking.date, booking.scheduled_start.to_i, booking.scheduled_ends_at&.to_i,
       location.name, location.address].to_json
    )
  end

  def self.record(booking, kind, **options)
    audiences(booking, kind, options).each do |notice_kind, users|
      next unless BookingNotificationSetting.for(booking.program, notice_kind).enabled

      event_key = "#{booking.id}:#{notice_kind}:#{options[:key] || booking.lock_version}"
      users.each do |recipient|
        find_or_create_by!(event_key: event_key, recipient_id: recipient.id) do |notice|
          notice.assign_attributes(record_attributes(booking, notice_kind, options))
        end
      end
    end
  end

  # Participants and coordinators receive separate kinds so each audience gets its own template.
  def self.audiences(booking, kind, options)
    participant = options[:audience] == :coordinators ? [] : [booking.user]
    coordinators = options[:audience] == :participant ? [] : coordinator_recipients(booking, kind, options)
    return { kind => coordinators } if BookingNotificationSetting::COORDINATOR_ONLY.include?(kind)

    copy = NotificationCatalog::COORDINATOR_COPIES[kind]
    copy ? { kind => participant, copy => coordinators } : { kind => participant }
  end

  def self.coordinator_recipients(booking, kind, options)
    return [] if BookingNotificationSetting::SCHEDULED.include?(kind) && kind != 'coordinator_alert'

    coordinators(booking.program).reject { |user| user.id.in?([options[:actor_id], booking.user_id]) }
  end

  def self.record_attributes(booking, kind, options)
    { booking: booking, kind: kind, previous_booking: options[:previous],
      signature: signature(booking), expires_at: expiry(booking, kind),
      attendance_revision: booking.attendance_changes.size, scheduled_for: options[:scheduled_for],
      previous_location: options[:previous_location] }
  end

  def self.expiry(booking, kind)
    NotificationCatalog.base_kind(kind) == 'booking_canceled' ? 1.day.from_now : booking.scheduled_start
  end

  def self.created(booking, previous: nil, actor_id: nil)
    return record(booking, 'booking_created', actor_id: actor_id) unless previous
    if previous.user_id == booking.user_id
      return record(booking, 'booking_changed', actor_id: actor_id,
                                                previous: previous)
    end

    record(previous, 'booking_canceled', actor_id: actor_id, audience: :participant)
    record(booking, 'booking_created', actor_id: actor_id, audience: :participant)
    record(booking, 'booking_changed', actor_id: actor_id, previous: previous, audience: :coordinators)
  end

  def queue
    self.class.with_session do |session|
      session.with_transaction do
        reload
        next unless state == 'pending'

        update!(state: 'queued')
        EmailDelivery.enqueue_in_transaction('booking_notification', self, session: session)
      end
    end
  end

  def message
    return unless BookingNotificationEligibility.new(self).allowed?

    BookingNotificationMailer.notify(self)
  end

  def scheduled?
    BookingNotificationSetting::SCHEDULED.include?(kind)
  end
end
