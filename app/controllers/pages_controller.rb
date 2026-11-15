# frozen_string_literal: true

class PagesController < ApplicationController
  before_action :require_authentication, except: %i[about privacy terms]

  def home
    memberships = ProgramMembership.participants.where(user_id: current_user.id).index_by(&:program_id)
    @booking_access = memberships.transform_values { |membership| BookingAccess.new(membership) }
    @upcoming_bookings = Booking.upcoming.where(user_id: current_user.id, :program_id.in => memberships.keys)
                                .includes(:program).to_a.sort_by(&:scheduled_start)
  end

  def about; end
  def privacy; end
  def terms; end
end
