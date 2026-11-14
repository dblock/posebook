# frozen_string_literal: true

class BookingMutation
  include ProgramScheduleLock
  include BookingRecords

  class Invalid < StandardError; end
  class Conflict < StandardError; end
  class Stale < Conflict; end

  def initialize(program:, user:)
    @program = program
    @user = user
  end

  def book(date:)
    run do
      raise Invalid, @program.message('bookings.already_scheduled') if claims.exists?

      selected = available_date(date)
      check_gender!(selected)
      @booking = create_record(selected)
      BookingClaim.create!(program: @program, user: @user, booking: @booking,
                           date: @booking.date, ends_at: @booking.ends_at)
    end
  end

  def change(booking:, date:, reason:, version: booking.lock_version)
    run do |session|
      original = reschedulable_booking(booking.id, version: version)
      selected = rescheduling_date(original, date)
      original.close!('rescheduled', explanation(reason), @user, session: session)
      @booking = create_record(selected, previous: original)
      claim = claims.find_by(booking_id: original.id)
      claim.update!(booking: @booking, date: @booking.date, ends_at: @booking.ends_at)
    end
  end

  def cancel(booking:, reason:, version: booking.lock_version)
    run(booking_access: false) do |session|
      original = active_booking(booking.id, version: version)
      original.close!('canceled', explanation(reason), @user, session: session)
      removed = BookingClaim.collection.find(booking_id: original.id).find_one_and_delete(session: session)
      raise Conflict, @program.message('bookings.conflict') unless removed

      @booking = original.reload
    end
  end

  private

  def run(booking_access: true)
    verify_participant!
    expire_claims
    with_schedule_lock do |session|
      check_booking_access!(booking_access)
      yield session
    end
    @booking
  rescue Mongo::Error::OperationFailure => e
    raise unless e.code == 11_000

    raise Conflict, @program.message('bookings.conflict')
  end

  def check_booking_access!(required)
    verify_participant!
    return unless required

    access = BookingAccess.new(@program.memberships.participants.where(user_id: @user.id).first)
    raise Invalid, access.reason unless access.allowed?
  end

  def verify_participant!
    return if @user.reload.active? && @program.participant?(@user)

    raise Invalid,
          @program.message('bookings.participant_required')
  end

  def check_gender!(date, excluding: nil)
    decision = BookingGenderRule.new(@program, excluding: excluding).evaluate(date, @user)
    raise Invalid, decision.message if decision
  end

  def rescheduling_date(original, value)
    date = available_date(value, excluding: original.id)
    raise Invalid, @program.message('bookings.different_date') if date == original.date

    check_gender!(date, excluding: original.id)
    date
  end

  def claims
    BookingClaim.where(program_id: @program.id, user_id: @user.id)
  end

  def active_booking(id, version:)
    booking = Booking.where(program_id: @program.id, user_id: @user.id).find(id)
    booking.assert_version!(version)
    booking
  end

  def reschedulable_booking(id, version:)
    booking = active_booking(id, version: version)
    raise Invalid, @program.message('bookings.rescheduling_locked') if booking.rescheduling_locked?

    booking
  end
end
