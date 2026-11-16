# frozen_string_literal: true

class ParticipantHistory
  PER_PAGE = 50

  attr_reader :pagination

  def initialize(user, cursor: nil)
    @user = user
    @pagination = CursorPage.new(records.includes(:previous_booking, program: :venue).order_by(date: :desc),
                                 cursor: cursor, per_page: PER_PAGE)
  end

  def bookings
    pagination.records
  end

  def count
    @count ||= records.count
  end

  private

  def records
    Booking.where(user_id: @user.id)
  end
end
