# frozen_string_literal: true

class GoogleCalendarSync
  include Mongoid::Document
  include Mongoid::Timestamps

  belongs_to :program, inverse_of: nil
  belongs_to :booking, inverse_of: nil
  field :revision, type: Integer, default: 0
  field :synced_revision, type: Integer, default: 0
  field :due_at, type: Time
  field :lease_until, type: Time
  field :lease_token, type: String
  field :attempts, type: Integer, default: 0
  field :last_error, type: String
  field :fingerprint, type: String
  field :synced_at, type: Time
  %i[rsvp_status rsvp_calendar_id rsvp_fingerprint].each { |name| field name, type: String }
  field :rsvp_checked_at, type: Time
  field :rsvp_booking_id, type: BSON::ObjectId
  index({ due_at: 1, lease_until: 1 })
  index({ program_id: 1 })

  def self.enqueue(booking, session: nil)
    return unless GoogleCalendarConnection.exists?(program_id: booking.program_id, enabled: true)

    root = booking
    root = root.previous_booking while root.previous_booking_id
    collection.find(_id: root.id).update_one(
      { '$set' => { program_id: booking.program_id, booking_id: booking.id, due_at: Time.current,
                    updated_at: Time.current },
        '$inc' => { revision: 1 },
        '$setOnInsert' => { synced_revision: 0, attempts: 0,
                            created_at: Time.current } }, upsert: true, session: session
    )
  end

  def self.reconcile
    ids = GoogleCalendarConnection.where(enabled: true).distinct(:program_id)
    bookings = Booking.upcoming.where(:program_id.in => ids)
    bookings.each { |booking| enqueue(booking) }
  end

  def self.process_next
    token = SecureRandom.hex(16)
    record = collection.find(
      due_at: { '$lte' => Time.current },
      '$or' => [{ lease_until: nil }, { lease_until: { '$lte' => Time.current } }]
    ).find_one_and_update(
      { '$set' => { lease_token: token, lease_until: 5.minutes.from_now } },
      return_document: :after, sort: { due_at: 1 }
    )
    return unless record

    find(record['_id']).deliver(token)
    record['_id']
  end

  def deliver(token)
    connection = GoogleCalendarConnection.where(program_id: program_id, enabled: true).first
    return finish(token) unless connection
    return retry_later(token, 'organizer access required') unless connection.authorized?

    synchronize(connection, token)
  rescue StandardError => e
    # Provider errors may contain contacts or tokens; persist only a safe classification.
    retry_later(token, e.class.name)
  end

  def event_id
    "posebook#{id}"
  end

  def payload_fingerprint(connection, payload = GoogleCalendarEvent.new(booking, connection).build)
    Digest::SHA256.hexdigest("#{connection.calendar_id}:#{payload.to_json}")
  end

  private

  def synchronize(connection, token)
    return deliver_event(connection, token) unless booking.status == 'canceled'

    cancel(connection.service, connection.calendar_id)
    finish(token, fingerprint: nil)
  end

  def deliver_event(connection, token)
    payload = GoogleCalendarEvent.new(booking, connection).build
    digest = payload_fingerprint(connection, payload)
    save_event(connection.service, connection.calendar_id, payload) unless digest == fingerprint
    finish(token, fingerprint: digest)
  end

  def save_event(service, calendar_id, payload)
    payload.id = event_id
    service.insert_event(calendar_id, payload, send_updates: 'all')
  rescue Google::Apis::ClientError => e
    raise unless e.status_code == 409

    service.update_event(calendar_id, event_id, payload, send_updates: 'all')
  end

  def cancel(service, calendar_id)
    service.delete_event(calendar_id, event_id, send_updates: 'all')
  rescue Google::Apis::ClientError => e
    raise unless [404, 410].include?(e.status_code)
  end

  def finish(token, **changes)
    collection.find(_id: id, lease_token: token).update_one(
      '$set' => changes.merge(synced_revision: revision, synced_at: Time.current, attempts: 0,
                              last_error: nil, lease_until: nil, lease_token: nil)
    )
    collection.find(_id: id, revision: revision, lease_token: nil).update_one('$set' => { due_at: nil })
  end

  def retry_later(token, classification)
    count = attempts + 1
    collection.find(_id: id, lease_token: token).update_one(
      '$set' => { attempts: count, last_error: classification, lease_until: nil, lease_token: nil,
                  due_at: Time.current + [30 * (2**[count, 10].min), 3600].min.seconds }
    )
  end
end
