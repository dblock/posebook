# frozen_string_literal: true

class VenueSchedulesController < ApplicationController
  before_action :require_authentication
  before_action :find_venue
  rescue_from BookingMutation::Invalid, BookingMutation::Conflict, with: :show_conflict

  def show
    @exception = @venue.schedule_exceptions.where(date: params[:date]).first ||
                 @venue.schedule_exceptions.new(date: params[:date], start_time: @venue.start_time)
    load_schedule
  end

  def update
    @exception = VenueScheduleMutation.new(venue: @venue, user: current_user).call(schedule_params)
    if @exception.errors.empty?
      redirect_to venue_path(@venue, month: @exception.date.strftime('%Y-%m')), notice: t('venues.schedule_saved')
    else
      load_schedule
      render :show, status: :unprocessable_content
    end
  end

  private

  def find_venue
    @venue = Venue.managed_by(current_user).find(params.expect(:venue_id))
  end

  def schedule_params
    params.expect(schedule: %i[date mode start_time reason]).to_h.symbolize_keys
  end

  def load_schedule
    @calendar = VenueCalendar.new(@venue)
    @exceptions = @venue.schedule_exceptions.where(:date.gte => @calendar.today).order_by(date: :asc)
  end

  def show_conflict(error)
    @exception = @venue.schedule_exceptions.new(schedule_params)
    @exception.errors.add(:base, error.message)
    load_schedule
    render :show, status: :unprocessable_content
  end
end
