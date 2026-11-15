# frozen_string_literal: true

class ParticipantHistory
  PER_PAGE = 50

  attr_reader :page

  def initialize(user, page:)
    @user = user
    @page = page.to_s.to_i.clamp(1, total_pages)
  end

  def bookings
    @bookings ||= records.includes(:previous_booking, program: :venue)
                         .order_by(date: :desc, created_at: :desc, id: :desc)
                         .skip((page - 1) * PER_PAGE).limit(PER_PAGE).to_a
  end

  def count
    @count ||= records.count
  end

  def total_pages
    [(count.to_f / PER_PAGE).ceil, 1].max
  end

  def first_number
    count.zero? ? 0 : ((page - 1) * PER_PAGE) + 1
  end

  def last_number
    [page * PER_PAGE, count].min
  end

  private

  def records
    Booking.where(user_id: @user.id)
  end
end
