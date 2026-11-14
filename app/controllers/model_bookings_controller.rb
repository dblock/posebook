# frozen_string_literal: true

class ModelBookingsController < ApplicationController
  before_action :require_authentication
  before_action :find_drawing_session
  before_action :require_model
  before_action :find_booking, except: :create
  before_action :require_booking_permission, only: %i[create edit update]
  rescue_from BookingMutation::Invalid, BookingMutation::Conflict, with: :show_error
  rescue_from BookingMutation::Stale, with: :show_stale_booking

  def edit
    load_calendar unless @booking.rescheduling_locked?
  end

  def create
    @booking = mutation.book(date: params[:date])
    finish_booking('bookings.created')
  end

  def update
    @booking = mutation.change(booking: @booking, date: params[:date], reason: params[:reason],
                               version: params[:booking_version])
    finish_booking('bookings.changed')
  end

  def cancellation; end

  def confirm
    @booking = AttendanceMutation.new(drawing_session: @drawing_session, user: current_user)
                                 .confirm(@booking.id, version: params[:booking_version])
    finish_booking('bookings.attendance_confirmed')
  end

  def cancel
    @booking = mutation.cancel(booking: @booking, reason: params[:reason], version: params[:booking_version])
    finish_booking('bookings.canceled')
  end

  private

  def require_booking_permission
    @booking_access = ModelBookingAccess.new(@drawing_session.memberships.models.where(user_id: current_user.id).first)
    @can_book = @booking_access.allowed?
    redirect_to drawing_session_path(@drawing_session), alert: @booking_access.reason unless @can_book
  end

  def find_drawing_session
    @drawing_session = DrawingSession.visible_to(current_user).find(params.expect(:drawing_session_id))
  end

  def require_model
    @can_book = @drawing_session.model?(current_user)
    head :forbidden unless @can_book
  end

  def find_booking
    records = %w[edit cancellation].include?(action_name) ? ModelBooking.upcoming : ModelBooking.all
    @booking = records.where(drawing_session_id: @drawing_session.id, user_id: current_user.id).find(params.expect(:id))
  end

  def mutation
    BookingMutation.new(drawing_session: @drawing_session, user: current_user)
  end

  def finish_booking(message)
    redirect_to drawing_session_path(@drawing_session, month: @booking.date.strftime('%Y-%m')), notice: t(message)
  end

  def load_calendar
    @calendar = DrawingSessionCalendar.new(@drawing_session, month: params[:month] || @booking.date.strftime('%Y-%m'))
    @my_booking = @booking
    @changing_booking = @booking
  end

  def show_error(error)
    if %w[create confirm].include?(action_name)
      return redirect_to drawing_session_path(@drawing_session, month: params[:date]&.to_s&.first(7)),
                         alert: error.message
    end

    load_calendar
    flash.now[:alert] = error.message
    render(action_name == 'cancel' ? :cancellation : :edit, status: :unprocessable_content)
  end

  def show_stale_booking(error)
    redirect_to drawing_session_path(@drawing_session), alert: error.message
  end
end
