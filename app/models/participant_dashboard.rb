# frozen_string_literal: true

class ParticipantDashboard
  def initialize(user)
    @user = user
  end

  def upcoming_bookings
    @upcoming_bookings ||= Booking.upcoming.where(user_id: @user.id, :program_id.in => memberships.keys)
                                  .includes(:program).to_a.sort_by(&:scheduled_start)
  end

  def access_for(program_id)
    @access ||= memberships.transform_values { |membership| BookingAccess.new(membership) }
    @access.fetch(program_id)
  end

  def bookable_programs
    booked = upcoming_bookings.map(&:program_id)
    memberships.values.filter_map do |membership|
      membership.program if booked.exclude?(membership.program_id) && access_for(membership.program_id).allowed?
    end.sort_by(&:name)
  end

  private

  def memberships
    @memberships ||= ProgramMembership.participants.where(user_id: @user.id).includes(:program).index_by(&:program_id)
  end
end
