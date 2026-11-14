# frozen_string_literal: true

class OrganizerBookingsController < ApplicationController
  before_action :require_authentication
  before_action :find_venue
  before_action :find_booking, only: %i[edit update cancel]
  rescue_from BookingMutation::Invalid, BookingMutation::Conflict, with: :show_error

  def new; end
  def edit; end

  def create
    @booking = mutation.create(booking_params)
    finish_booking
  end

  def update
    @booking = mutation.update(@booking.id, booking_params)
    finish_booking
  end

  def cancel
    @booking = mutation.cancel(@booking.id, reason: booking_params[:reason])
    finish_booking
  end

  private

  def find_venue
    @venue = Venue.managed_by(current_user).find(params.expect(:venue_id))
    ids = @venue.memberships.models.distinct(:user_id)
    @models = User.active.where(:id.in => ids).order_by(name: :asc).to_a
  end

  def find_booking
    @booking = ModelBooking.upcoming.where(venue_id: @venue.id).find(params.expect(:id))
    @models << @booking.user unless @models.any? { |model| model.id == @booking.user_id }
  end

  def booking_params
    params.expect(booking: %i[date user_id attendance reason]).to_h.symbolize_keys
  end

  def mutation
    OrganizerBookingMutation.new(venue: @venue, user: current_user)
  end

  def finish_booking
    redirect_to venue_path(@venue, month: @booking.date.strftime('%Y-%m')), notice: t('bookings.organizer_saved')
  end

  def show_error(error)
    flash.now[:alert] = error.message
    render(action_name == 'create' ? :new : :edit, status: :unprocessable_content)
  end
end
