# frozen_string_literal: true

class OrganizerBookingMutation
  include ProgramScheduleLock
  include BookingRecords

  def initialize(program:, user:)
    @program = program
    @user = user
  end

  def create(attributes)
    run do |session|
      @booking = build_booking(attributes)
      BookingClaim.create!(program: @program, user: @booking.user, booking: @booking,
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
      removed = BookingClaim.collection.find(booking_id: @booking.id).delete_one(session: session)
      raise BookingMutation::Conflict, @program.message('bookings.conflict') unless removed.deleted_count == 1

      @booking.reload
    end
  end

  private

  def run
    expire_claims
    with_schedule_lock do |session|
      unless @user.reload.active? && @program.managed_by?(@user)
        raise BookingMutation::Invalid,
              @program.message('bookings.manager_required')
      end

      yield session
    end
    @booking
  rescue Mongo::Error::OperationFailure => e
    raise unless e.code == 11_000

    raise BookingMutation::Conflict, @program.message('bookings.conflict')
  end

  def active_booking(id, version:)
    booking = Booking.where(program_id: @program.id).find(id)
    booking.assert_version!(version)
    booking
  end

  def build_booking(attributes, previous: nil)
    date = available_date(attributes[:date], excluding: previous&.id)
    participant = if previous
                    replacement_participant(previous,
                                            attributes[:user_id])
                  else
                    participant_for(attributes[:user_id])
                  end
    reason = gender_override(date, participant, attributes, excluding: previous&.id)
    create_record(date, user: participant, previous: previous, gender_override_reason: reason)
  end

  def gender_override(date, participant, attributes, excluding:)
    message = BookingGenderRule.new(@program, excluding: excluding).blocked_reason(date, participant)
    return unless message

    raise BookingMutation::Invalid, message if participant.gender.blank? || attributes[:override_gender_rule] != '1'

    explanation(attributes[:reason])
  end

  def participant_for(id)
    membership = @program.memberships.participants.where(user_id: id).first
    raise BookingMutation::Invalid, @program.message('bookings.participant_required') unless membership&.user&.active?

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

  def replacement_participant(original, id)
    id == original.user_id.to_s ? original.user : participant_for(id)
  end

  def replace_claim(original, replacement)
    BookingClaim.find_by(booking_id: original.id).update!(
      user_id: replacement.user_id, booking: replacement, date: replacement.date, ends_at: replacement.ends_at
    )
  end

  def update_attendance(attributes, session)
    value = attributes[:attendance]
    unless %w[confirmed unconfirmed].include?(value)
      raise BookingMutation::Invalid, @program.message('bookings.attendance_required')
    end

    reason = attributes[:reason].presence || @program.message('bookings.organizer_created')
    @booking.record_attendance!(value == 'confirmed', @user, explanation(reason), session: session)
  end
end
