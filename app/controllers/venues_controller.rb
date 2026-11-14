# frozen_string_literal: true

class VenuesController < ApplicationController
  before_action :require_authentication
  before_action :require_system_admin, only: %i[new create edit update]
  before_action :find_venue, only: %i[show edit update]
  rescue_from Mongo::Error::OperationFailure, with: :handle_slug_conflict

  def index
    @venues = Venue.visible_to(current_user).order_by(name: :asc)
  end

  def show
    load_calendar
    @manage_schedule = @venue.managed_by?(current_user)
    @invitations = @venue.model_invitations.order_by(created_at: :desc) if @manage_schedule
  end

  def new
    @venue = Venue.new
  end

  def edit; end

  def create
    @venue = Venue.new(venue_params)
    if @venue.save
      redirect_to @venue, notice: t('venues.created')
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @venue.update(venue_params)
      redirect_to @venue, notice: t('venues.updated')
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def handle_slug_conflict(error)
    raise error unless error.code == 11_000

    @venue.errors.add(:custom_slug, :taken)
    render(action_name == 'create' ? :new : :edit, status: :unprocessable_content)
  end

  def load_calendar
    @calendar = VenueCalendar.new(@venue, month: params[:month])
    @can_book = @venue.model?(current_user)
    @my_booking = @calendar.current_booking(current_user)
    @booking_history = @calendar.history_for(current_user)
  end

  def find_venue
    @venue = Venue.visible_to(current_user).find(params.expect(:id))
  end

  def venue_params
    params.expect(venue: [:name, :custom_slug, :address, :time_zone, :model_pay, :instructions, :booking_horizon_months,
                          { available_weekdays: [] }])
  end
end
