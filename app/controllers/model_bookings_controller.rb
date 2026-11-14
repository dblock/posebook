# frozen_string_literal: true

class ModelBookingsController < ApplicationController
  before_action :require_authentication
  before_action :find_venue
  before_action :require_model
  before_action :find_booking, except: :create
  before_action :require_booking_permission, only: %i[create edit update]
  rescue_from BookingMutation::Invalid, BookingMutation::Conflict, with: :show_error

  def edit
    load_calendar unless @booking.rescheduling_locked?
  end

  def create
    @booking = mutation.book(date: params[:date])
    finish_booking('bookings.created')
  end

  def update
    @booking = mutation.change(booking: @booking, date: params[:date], reason: params[:reason])
    finish_booking('bookings.changed')
  end

  def cancellation; end

  def confirm
    @booking = AttendanceMutation.new(venue: @venue, user: current_user).confirm(@booking.id)
    finish_booking('bookings.attendance_confirmed')
  end

  def cancel
    @booking = mutation.cancel(booking: @booking, reason: params[:reason])
    finish_booking('bookings.canceled')
  end

  private

  def require_booking_permission
    @booking_access = ModelBookingAccess.new(@venue.memberships.models.where(user_id: current_user.id).first)
    @can_book = @booking_access.allowed?
    redirect_to venue_path(@venue), alert: @booking_access.reason unless @can_book
  end

  def find_venue
    @venue = Venue.visible_to(current_user).find(params.expect(:venue_id))
  end

  def require_model
    @can_book = @venue.model?(current_user)
    head :forbidden unless @can_book
  end

  def find_booking
    @booking = ModelBooking.upcoming.where(venue_id: @venue.id, user_id: current_user.id).find(params.expect(:id))
  end

  def mutation
    BookingMutation.new(venue: @venue, user: current_user)
  end

  def finish_booking(message)
    redirect_to venue_path(@venue, month: @booking.date.strftime('%Y-%m')), notice: t(message)
  end

  def load_calendar
    @calendar = VenueCalendar.new(@venue, month: params[:month] || @booking.date.strftime('%Y-%m'))
    @my_booking = @booking
    @changing_booking = @booking
  end

  def show_error(error)
    if %w[create confirm].include?(action_name)
      return redirect_to venue_path(@venue, month: params[:date]&.to_s&.first(7)), alert: error.message
    end

    load_calendar
    flash.now[:alert] = error.message
    render(action_name == 'cancel' ? :cancellation : :edit, status: :unprocessable_content)
  end
end
