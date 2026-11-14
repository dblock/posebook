# frozen_string_literal: true

module BookingAttendance
  extend ActiveSupport::Concern

  included do
    field :attendance_confirmed_at, type: Time
    field :attendance_confirmed_by_id, type: BSON::ObjectId
    field :attendance_changes, type: Array, default: []
    attr_readonly :attendance_confirmed_at, :attendance_confirmed_by_id, :attendance_changes
  end

  def attendance_confirmed?
    attendance_confirmed_at.present?
  end

  def confirmation_opens_on
    date - 7
  end

  def confirmation_open?
    status == 'confirmed' && booking_today >= confirmation_opens_on && scheduled_start > Time.current
  end

  def attendance_overdue?
    status == 'confirmed' && ends_at > Time.current && rescheduling_locked? && !attendance_confirmed?
  end

  def rescheduling_locked?
    booking_today >= date - 5
  end

  def record_attendance!(confirmed, actor, explanation, session:)
    return if attendance_confirmed? == confirmed

    change = { confirmed: confirmed, changed_at: Time.current, changed_by_id: actor.id, reason: explanation }
    result = self.class.collection.find(_id: id, status: 'confirmed', ends_at: { '$gt' => Time.current }).update_one(
      { '$set' => attendance_fields(confirmed, actor), '$push' => { attendance_changes: change } }, session: session
    )
    raise BookingMutation::Conflict, I18n.t('bookings.conflict') unless result.modified_count == 1

    reload
  end

  private

  def attendance_fields(confirmed, actor)
    { attendance_confirmed_at: confirmed ? Time.current : nil,
      attendance_confirmed_by_id: confirmed ? actor.id : nil, updated_at: Time.current }
  end

  def booking_today
    Time.current.in_time_zone(time_zone).to_date
  end
end
