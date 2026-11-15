# frozen_string_literal: true

class VenuesController < ApplicationController
  before_action :require_authentication, except: %i[show photos programs]
  before_action :require_system_admin, only: %i[new create]
  before_action :find_venue, only: %i[show photos programs edit update]
  rescue_from Mongo::Error::OperationFailure, with: :handle_slug_conflict

  def index
    @venues = Venue.preload_primary_photos(Venue.visible_to(current_user).order_by(name: :asc))
  end

  def show; end

  def photos; end

  def programs
    @programs = Program.preload_primary_photos(@venue.programs.includes(:venue).order_by(name: :asc))
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
    scope = %w[show photos programs].include?(action_name) ? Venue.all : Venue.coordinated_by(current_user)
    @venue = scope.find(params.expect(:id))
  end

  def venue_params
    params.expect(venue: %i[name custom_slug address instagram_handle google_maps_url])
  end

  def handle_slug_conflict(error)
    raise error unless error.code == 11_000

    @venue.errors.add(:custom_slug, :taken)
    render(action_name == 'create' ? :new : :edit, status: :unprocessable_content)
  end
end
