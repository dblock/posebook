# frozen_string_literal: true

class OrganizerBookingMutation
  include DrawingSessionScheduleLock
  include BookingRecords

  def initialize(drawing_session:, user:)
    @drawing_session = drawing_session
    @user = user
  end

  def create(attributes)
    run do |session|
      @booking = build_booking(attributes)
      ModelBookingClaim.create!(drawing_session: @drawing_session, user: @booking.user, model_booking: @booking,
                                date: @booking.date, ends_at: @booking.ends_at)
      update_attendance(attributes, session)
    end
  end

  def update(id, attributes)
    run do |session|
      original = active_booking(id, version: attributes[:lock_version])
      @booking = replace_if_changed(original, attributes, session)
      update_attendance(attributes, session)
    end
  end

  def cancel(id, reason:, version:)
    run do |session|
      @booking = active_booking(id, version: version)
      @booking.close!('canceled', explanation(reason), @user, session: session)
      removed = ModelBookingClaim.collection.find(model_booking_id: @booking.id).delete_one(session: session)
      raise BookingMutation::Conflict, I18n.t('bookings.conflict') unless removed.deleted_count == 1

      @booking.reload
    end
  end

  private

  def run
    expire_claims
    with_schedule_lock do |session|
      unless @user.reload.active? && @drawing_session.managed_by?(@user)
        raise BookingMutation::Invalid,
              I18n.t('bookings.manager_required')
      end

      yield session
    end
    @booking
  rescue Mongo::Error::OperationFailure => e
    raise unless e.code == 11_000

    raise BookingMutation::Conflict, I18n.t('bookings.conflict')
  end

  def active_booking(id, version:)
    booking = ModelBooking.where(drawing_session_id: @drawing_session.id).find(id)
    booking.assert_version!(version)
    booking
  end

  def build_booking(attributes, previous: nil)
    date = available_date(attributes[:date], excluding: previous&.id)
    model = previous ? replacement_model(previous, attributes[:user_id]) : model_for(attributes[:user_id])
    reason = gender_override(date, model, attributes, excluding: previous&.id)
    create_record(date, user: model, previous: previous, gender_override_reason: reason)
  end

  def gender_override(date, model, attributes, excluding:)
    message = BookingGenderRule.new(@drawing_session, excluding: excluding).blocked_reason(date, model)
    return unless message

    raise BookingMutation::Invalid, message if model.gender.blank? || attributes[:override_gender_rule] != '1'

    explanation(attributes[:reason])
  end

  def model_for(id)
    membership = @drawing_session.memberships.models.where(user_id: id).first
    raise BookingMutation::Invalid, I18n.t('bookings.model_required') unless membership&.user&.active?

    membership.user
  end

  def replace_if_changed(original, attributes, session)
    explanation(attributes[:reason])
    return original if attributes.values_at(:date, :user_id) == [original.date.iso8601, original.user_id.to_s]

    original.close!('rescheduled', explanation(attributes[:reason]), @user, session: session)
    replacement = build_booking(attributes, previous: original)
    replace_claim(original, replacement)
    replacement
  end

  def replacement_model(original, id)
    id == original.user_id.to_s ? original.user : model_for(id)
  end

  def replace_claim(original, replacement)
    ModelBookingClaim.find_by(model_booking_id: original.id).update!(
      user_id: replacement.user_id, model_booking: replacement, date: replacement.date, ends_at: replacement.ends_at
    )
  end

  def update_attendance(attributes, session)
    value = attributes[:attendance]
    unless %w[confirmed unconfirmed].include?(value)
      raise BookingMutation::Invalid, I18n.t('bookings.attendance_required')
    end

    reason = attributes[:reason].presence || I18n.t('bookings.organizer_created')
    @booking.record_attendance!(value == 'confirmed', @user, explanation(reason), session: session)
  end
end
