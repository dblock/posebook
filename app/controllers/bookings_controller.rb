# frozen_string_literal: true

class BookingsController < ApplicationController
  before_action :require_authentication
  before_action :find_program
  before_action :require_participant
  before_action :find_booking, except: :create
  before_action :require_booking_permission, only: %i[create edit update]
  rescue_from BookingMutation::Invalid, BookingMutation::Conflict, with: :show_error
  rescue_from BookingMutation::Stale, with: :show_stale_booking

  def edit
    load_calendar unless @booking.rescheduling_locked?
  end

  def create
    return show_booking_confirmation unless params[:confirmed] == '1'

    @booking = mutation.book(date: params[:date], schedule_revision: submitted_schedule_revision)
    finish_booking('bookings.created')
  end

  def update
    @booking = mutation.change(booking: @booking, date: params[:date], reason: params[:reason],
                               version: params[:booking_version])
    finish_booking('bookings.changed')
  end

  def cancellation; end

  def confirm
    @booking = AttendanceMutation.new(program: @program, user: current_user)
                                 .confirm(@booking.id, version: params[:booking_version])
    finish_booking('bookings.attendance_confirmed')
  end

  def cancel
    @booking = mutation.cancel(booking: @booking, reason: params[:reason], version: params[:booking_version])
    finish_booking('bookings.canceled')
  end

  private

  def submitted_schedule_revision
    revision = params[:schedule_revision]
    return revision if revision.is_a?(String) && revision.match?(/\A(?:0|[1-9]\d*)\z/)

    raise BookingMutation::Stale, @program.message('bookings.stale')
  end

  def show_booking_confirmation
    @date = Date.iso8601(params[:date].to_s)
    @calendar = ProgramCalendar.new(@program, month: @date.strftime('%Y-%m'))
    raise BookingMutation::Invalid, @program.message('bookings.invalid_date') if @calendar.blocked_reason(@date)
    raise BookingMutation::Conflict, @program.message('bookings.date_taken') if @calendar.displayed_bookings[@date]

    render :confirmation
  rescue ArgumentError
    raise BookingMutation::Invalid, @program.message('bookings.invalid_date')
  end

  def require_booking_permission
    @booking_access = BookingAccess.new(@program.memberships.participants.where(user_id: current_user.id).first)
    @can_book = @booking_access.allowed?
    destination = @program.booking_active? ? program_path(@program) : profile_path
    redirect_to destination, alert: @booking_access.reason unless @can_book
  end

  def find_program
    @program = Program.visible_to(current_user).find(params.expect(:program_id))
  end

  def require_participant
    @can_book = @program.participant?(current_user)
    head :forbidden unless @can_book
  end

  def find_booking
    records = %w[edit cancellation].include?(action_name) ? Booking.upcoming : Booking.all
    @booking = records.where(program_id: @program.id, user_id: current_user.id).find(params.expect(:id))
  end

  def mutation
    BookingMutation.new(program: @program, user: current_user)
  end

  def finish_booking(message)
    destination = if @program.reload.booking_active?
                    calendar_program_path(@program, month: @booking.date.strftime('%Y-%m'))
                  else
                    profile_path
                  end
    redirect_to destination,
                notice: @program.message(message)
  end

  def load_calendar
    @calendar = ProgramCalendar.new(@program, month: params[:month] || @booking.date.strftime('%Y-%m'))
    @my_booking = @booking
    @changing_booking = @booking
  end

  def show_error(error)
    return redirect_to error_calendar_path, alert: error.message if %w[create confirm].include?(action_name)

    load_calendar
    flash.now[:alert] = error.message
    render(action_name == 'cancel' ? :cancellation : :edit, status: :unprocessable_content)
  end

  def error_calendar_path
    return profile_path unless @program.reload.booking_active?

    month = params[:date]&.to_s&.first(7)
    calendar_program_path(@program, month: month)
  end

  def show_stale_booking(error)
    destination = @program.reload.booking_active? ? program_path(@program) : profile_path
    redirect_to destination, alert: error.message
  end
end
