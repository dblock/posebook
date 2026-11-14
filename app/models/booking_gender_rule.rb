# frozen_string_literal: true

class BookingGenderRule
  def initialize(program, excluding: nil)
    @program = program
    @excluding = excluding
    @schedule = ProgramSchedule.new(program, from: nil)
    @bookings = {}
  end

  def evaluate(date, user)
    genders = @program.no_consecutive_genders
    return if genders.empty?

    gender = user.gender
    return decision(:gender_required, overridable: false) if gender.blank?
    return unless genders.include?(gender)

    dates = [-1, 1].map { |direction| adjacent_date(date, direction) }
    return unless bookings_on(dates).any? { |booking| booking.user.gender == gender }

    decision(:gender_restricted, overridable: true)
  end

  private

  def decision(code, overridable:)
    BookingRuleDecision.new(code: code, message: @program.message("bookings.#{code}"), overridable: overridable)
  end

  def adjacent_date(date, direction)
    candidate = date + direction
    candidate += direction until scheduled?(candidate)
    candidate
  end

  def scheduled?(date)
    @schedule.starts_at(date).present?
  rescue ArgumentError
    false
  end

  def bookings_on(dates)
    missing = dates - @bookings.keys
    @bookings.merge!(missing.index_with(nil))
    records = Booking.where(program_id: @program.id, status: 'confirmed', :id.ne => @excluding,
                            :date.in => missing)
    @bookings.merge!(records.includes(:user).index_by(&:date)) if missing.any?
    @bookings.values_at(*dates).compact
  end
end
