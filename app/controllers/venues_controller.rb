# frozen_string_literal: true

class VenuesController < ApplicationController
  include SlugConflictHandling

  before_action :require_authentication, except: %i[show photos programs]
  before_action :require_system_admin, only: %i[new create security]
  before_action :find_venue, only: %i[show photos programs edit update security]
  rescue_from LocationActivation::Forbidden, with: -> { head :forbidden }
  rescue_from LocationActivation::Invalid, with: -> { head :bad_request }

  def index
    records = Venue.visible_to(current_user).and(Venue.viewable_by(current_user).selector)
    @venues = Venue.preload_primary_photos(records.order_by(name: :asc))
  end

  def show; end

  def photos; end

  def programs
    records = Program.viewable_by(current_user).where(venue_id: @venue.id)
    @programs = Program.preload_primary_photos(records.includes(:venue).order_by(name: :asc))
  end

  def new
    @venue = Venue.new
  end

  def edit; end

  def security; end

  def create
    @venue = Venue.new(venue_params)
    if @venue.save
      redirect_to @venue, notice: t('venues.created')
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    return update_activation if params.key?(:active)

    if @venue.update(venue_params)
      redirect_to @venue, notice: t('venues.updated')
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def update_activation
    @venue = LocationActivation.new(location: @venue, user: current_user).call(params[:active])
    redirect_to security_venue_path(@venue), notice: t('locations.access_updated')
  end

  def find_venue
    public_action = %w[show photos programs].include?(action_name)
    scope = public_action ? Venue.all : Venue.coordinated_by(current_user)
    @venue = scope.find(params.expect(:id))
    head :not_found if public_action && !@venue.viewable_by?(current_user)
  end

  def venue_params
    params.expect(venue: %i[name custom_slug address instagram_handle google_maps_url])
  end
end
