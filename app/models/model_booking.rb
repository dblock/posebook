# frozen_string_literal: true

class ModelBooking
  include Mongoid::Document
  include Mongoid::Timestamps

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

  attr_readonly :venue_id, :user_id, :date, :time_zone, :ends_at, :starts_at, :time_changes, :previous_booking_id
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

  def rescheduling_locked?
    scheduled_start < 1.week.from_now
  end

  def change_time!(start, explanation, actor, session:)
    return if scheduled_start == start

    change = { from: scheduled_start, to: start, reason: explanation, changed_at: Time.current,
               changed_by_id: actor.id }
    result = self.class.collection.find(_id: id, status: 'confirmed', ends_at: { '$gt' => Time.current }).update_one(
      { '$set' => { starts_at: start, updated_at: Time.current },
        '$push' => { time_changes: change } }, session: session
    )
    raise BookingMutation::Conflict, I18n.t('bookings.conflict') unless result.modified_count == 1
  end

  def close!(new_status, explanation, actor, session:)
    result = self.class.collection.find(_id: id, status: 'confirmed', ends_at: { '$gt' => Time.current })
                 .find_one_and_update(
                   { '$set' => { status: new_status, reason: explanation, changed_at: Time.current,
                                 changed_by_id: actor.id, updated_at: Time.current } }, session: session
                 )
    raise BookingMutation::Conflict, I18n.t('bookings.conflict') unless result
  end

  def delete(*)
    raise HistoryRetained, 'Booking history cannot be deleted.'
  end

  def self.delete_all(*)
    raise HistoryRetained, 'Booking history cannot be deleted.'
  end
end
