# frozen_string_literal: true

class VenuesController < ApplicationController
  before_action :require_authentication
  before_action :require_system_admin, only: %i[new create edit update]
  before_action :find_venue, only: %i[show edit update]

  def index
    @venues = Venue.visible_to(current_user).order_by(name: :asc)
  end

  def show
    return unless current_user.system_admin?

    @organizers = @venue.memberships.schedule_managers.includes(:user).to_a
    @eligible_users = User.active.where(:id.nin => @organizers.map(&:user_id)).order_by(name: :asc)
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

  def find_venue
    @venue = Venue.visible_to(current_user).find(params.expect(:id))
  end

  def venue_params
    params.expect(venue: %i[name address time_zone model_pay instructions booking_horizon_months])
  end
end
