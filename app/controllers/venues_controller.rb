# frozen_string_literal: true

class VenuesController < ApplicationController
  before_action :remember_booking_destination, only: :show
  before_action :require_authentication, except: :show
  before_action :require_system_admin, only: %i[new create edit update]
  before_action :find_venue, only: %i[show edit update]
  rescue_from Mongo::Error::OperationFailure, with: :handle_slug_conflict

  def index
    @venues = Venue.visible_to(current_user).order_by(name: :asc)
  end

  def show
    @calendar = VenueCalendar.new(@venue, month: params[:month])
    @manage_schedule = current_user && @venue.managed_by?(current_user)
    @venue_member = @manage_schedule || (current_user && @venue.model?(current_user))
    load_calendar if @venue_member
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
    @venue = VenueSettingsUpdate.new(venue: @venue, user: current_user).call(venue_params)
    if @venue.errors.empty?
      redirect_to @venue, notice: t('venues.updated')
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def remember_booking_destination
    return if current_user || params[:booking_invitation] != '1'

    session[:booking_venue] = params[:id]
    require_authentication
  end

  def handle_slug_conflict(error)
    raise error unless error.code == 11_000

    @venue.errors.add(:custom_slug, :taken)
    render(action_name == 'create' ? :new : :edit, status: :unprocessable_content)
  end

  def load_calendar
    @booking_access = ModelBookingAccess.new(@venue.memberships.models.where(user_id: current_user.id).first)
    @can_book = @booking_access.allowed?
    @my_booking = @calendar.current_booking(current_user)
    @booking_history = @calendar.history_for(current_user)
  end

  def find_venue
    scope = action_name == 'show' ? Venue.all : Venue.visible_to(current_user)
    @venue = scope.find(params.expect(:id))
  end

  def venue_params
    params.expect(venue: [:name, :custom_slug, :address, :instagram_handle, :time_zone, :start_time, :model_pay,
                          :instructions, :booking_horizon_months,
                          { available_weekdays: [], no_consecutive_genders: [] }])
  end
end
