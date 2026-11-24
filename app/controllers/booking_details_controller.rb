# frozen_string_literal: true

class BookingDetailsController < ApplicationController
  before_action :remember_booking_page
  before_action :require_authentication

  # Everyone who may not view the booking gets the same not-found response.
  def show
    @program = Program.visible_to(current_user).find(params.expect(:program_id))
    @details = BookingDetails.find(@program, params.expect(:id), current_user)
    head :not_found unless @details
  end

  private

  # Signing in from an emailed booking link returns to that booking.
  def remember_booking_page
    session[:booking_page] = [params[:program_id], params[:id]] unless current_user
  end
end
