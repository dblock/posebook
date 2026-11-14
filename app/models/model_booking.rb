# frozen_string_literal: true

class ModelBooking
  include Mongoid::Document
  include Mongoid::Timestamps
  include BookingAttendance

  class HistoryRetained < StandardError; end

  belongs_to :venue, inverse_of: :model_bookings
  belongs_to :user, inverse_of: nil
  belongs_to :previous_booking, class_name: 'ModelBooking', inverse_of: nil, optional: true
  field :date, type: Date
  field :time_zone, type: String
  field :ends_at, type: Time
  field :status, type: String, default: 'confirmed'
  field :reason, type: String
  field :changed_at, type: Time
  field :changed_by_id, type: BSON::ObjectId
  field :starts_at, type: Time
  field :time_changes, type: Array, default: []
  field :created_by_id, type: BSON::ObjectId
  field :gender_override_reason, type: String
  field :lock_version, type: Integer, default: 0

  attr_readonly :venue_id, :user_id, :date, :time_zone, :ends_at, :starts_at, :time_changes, :previous_booking_id,
                :created_by_id, :gender_override_reason, :lock_version
  index({ venue_id: 1, user_id: 1, date: -1 })
  index({ venue_id: 1, status: 1, ends_at: 1 })
  index({ venue_id: 1, date: -1, created_at: -1 })
  scope :upcoming, -> { where(status: 'confirmed', :ends_at.gt => Time.current) }
  validates :date, :ends_at, :time_zone, presence: true
  validates :status, inclusion: { in: %w[confirmed canceled rescheduled] }
  validates :reason, presence: true, length: { maximum: 2000 }, if: -> { status != 'confirmed' }
  before_destroy do
    errors.add(:base, 'Booking history is retained.')
    throw(:abort)
  end

  def display_status
    status == 'confirmed' && ends_at <= Time.current ? 'Completed' : status.humanize
  end

  def scheduled_start
    starts_at || VenueSchedule.local_start(date, '18:30', time_zone)
  end

  def assert_version!(version)
    return if version.to_s == lock_version.to_s && status == 'confirmed' && ends_at > Time.current

    raise BookingMutation::Stale, I18n.t('bookings.stale')
  end

  def change_time!(start, explanation, actor, session:)
    return if scheduled_start == start

    change = { from: scheduled_start, to: start, reason: explanation, changed_at: Time.current,
               changed_by_id: actor.id }
    atomic_change!(
      { '$set' => { starts_at: start, updated_at: Time.current },
        '$push' => { time_changes: change } }, session: session
    )
  end

  def close!(new_status, explanation, actor, session:)
    atomic_change!(
      { '$set' => { status: new_status, reason: explanation, changed_at: Time.current,
                    changed_by_id: actor.id, updated_at: Time.current } }, session: session
    )
  end

  def delete(*)
    raise HistoryRetained, 'Booking history cannot be deleted.'
  end

  def self.delete_all(*)
    raise HistoryRetained, 'Booking history cannot be deleted.'
  end

  private

  def atomic_change!(changes, session:)
    version = lock_version.zero? ? { '$in' => [nil, 0] } : lock_version
    selector = { _id: id, status: 'confirmed', ends_at: { '$gt' => Time.current }, lock_version: version }
    result = self.class.collection.find(selector).update_one(
      changes.merge('$inc' => { lock_version: 1 }), session: session
    )
    raise BookingMutation::Stale, I18n.t('bookings.stale') unless result.modified_count == 1

    reload
  end
end
