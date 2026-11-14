# frozen_string_literal: true

class VenueCoordinatorsController < ApplicationController
  before_action :require_authentication
  before_action :require_system_admin
  before_action -> { @venue = Venue.find(params.expect(:venue_id)) }

  def index
    @coordinators = @venue.memberships.coordinators.includes(:user).to_a
  end

  def create
    user = User.active.where(email: params.expect(:email).to_s.strip.downcase).first
    return redirect_to venue_coordinators_path(@venue), alert: t('venues.coordinator_not_found') unless user

    VenueMembership.grant_coordinator_access(@venue, user)
    redirect_to venue_coordinators_path(@venue), notice: t('venues.coordinator_added')
  end

  def destroy
    @venue.memberships.coordinators.find(params.expect(:id)).revoke_coordinator_access
    redirect_to venue_coordinators_path(@venue), notice: t('venues.coordinator_removed')
  end
end
