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
    return unless BookingNotificationSetting.for(booking.program, kind).enabled

    recipients(booking, kind, options).each do |recipient|
      event_key = "#{booking.id}:#{kind}:#{options[:key] || booking.lock_version}"
      find_or_create_by!(event_key: event_key, recipient_id: recipient.id) do |notice|
        notice.assign_attributes(record_attributes(booking, kind, options))
      end
    end
  end

  def self.recipients(booking, kind, options)
    return [booking.user] if options[:audience] == :participant

    users = coordinator_recipients(booking, kind, options)
    users << booking.user unless BookingNotificationSetting::COORDINATOR_ONLY.include?(kind) ||
                                 options[:audience] == :coordinators
    users.uniq(&:id)
  end

  def self.coordinator_recipients(booking, kind, options)
    return [] if BookingNotificationSetting::SCHEDULED.include?(kind) && kind != 'coordinator_alert'

    coordinators(booking.program).reject { |user| user.id == options[:actor_id] }
  end

  def self.record_attributes(booking, kind, options)
    { booking: booking, kind: kind, previous_booking: options[:previous],
      signature: signature(booking), expires_at: expiry(booking, kind),
      attendance_revision: booking.attendance_changes.size, scheduled_for: options[:scheduled_for],
      previous_location: options[:previous_location] }
  end

  def self.expiry(booking, kind)
    kind == 'booking_canceled' ? 1.day.from_now : booking.scheduled_start
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
