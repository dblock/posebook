# frozen_string_literal: true

class OrganizerBookingsController < ApplicationController
  before_action :require_authentication
  before_action :find_program
  before_action :find_booking, only: %i[edit update cancel]
  rescue_from BookingMutation::Invalid, BookingMutation::Conflict, with: :show_error
  rescue_from BookingMutation::Stale, with: :show_stale_booking

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
    @booking = mutation.cancel(@booking.id, reason: booking_params[:reason], version: booking_params[:lock_version])
    finish_booking
  end

  private

  def find_program
    @program = Program.managed_by(current_user).find(params.expect(:program_id))
    ids = @program.memberships.participants.distinct(:user_id)
    @participants = User.active.where(:id.in => ids).order_by(name: :asc).to_a
  end

  def find_booking
    records = action_name == 'edit' ? Booking.upcoming : Booking.all
    @booking = records.where(program_id: @program.id).find(params.expect(:id))
    @participants << @booking.user unless @participants.any? { |participant| participant.id == @booking.user_id }
  end

  def booking_params
    params.expect(booking: %i[date user_id attendance reason override_gender_rule lock_version]).to_h.symbolize_keys
  end

  def mutation
    OrganizerBookingMutation.new(program: @program, user: current_user)
  end

  def finish_booking
    redirect_to program_path(@program, month: @booking.date.strftime('%Y-%m')),
                notice: @program.message('bookings.organizer_saved')
  end

  def show_error(error)
    flash.now[:alert] = error.message
    render(action_name == 'create' ? :new : :edit, status: :unprocessable_content)
  end

  def show_stale_booking(error)
    redirect_to program_path(@program), alert: error.message
  end
end
