# frozen_string_literal: true

# Read model for a single booking page. Only the booking's participant and viewers who manage the
# program (program/venue coordinators and system admins) may see it; moved-booking links are limited
# to bookings the same viewer could open.
class BookingDetails
  attr_reader :program, :booking, :viewer

  def self.find(program, id, viewer)
    booking = Booking.where(program_id: program.id, id: id).first
    details = new(program, booking, viewer) if booking
    details if details&.visible?
  end

  def initialize(program, booking, viewer)
    @program = program
    @booking = booking
    @viewer = viewer
  end

  def visible?
    own? || coordinator?
  end

  def own?
    booking.user_id == viewer.id
  end

  def coordinator?
    return @coordinator if defined?(@coordinator)

    @coordinator = program.managed_by?(viewer)
  end

  def upcoming?
    booking.status == 'confirmed' && booking.ends_at > Time.current
  end

  def can_book?
    BookingAccess.new(program.memberships.participants.where(user_id: viewer.id).first).allowed?
  end

  def replacement
    viewable(Booking.where(previous_booking_id: booking.id).first)
  end

  def previous
    viewable(booking.previous_booking)
  end

  private

  def viewable(other)
    other if other && (coordinator? || other.user_id == viewer.id)
  end
end
