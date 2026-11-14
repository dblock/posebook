# frozen_string_literal: true

class VenueCoordinatorsController < ApplicationController
  before_action :require_authentication
  before_action :require_system_admin
  before_action -> { @venue = Venue.find(params.expect(:venue_id)) }
  include CoordinatorInviting

  def destroy
    @venue.memberships.coordinators.find(params.expect(:id)).revoke_coordinator_access
    redirect_to venue_coordinators_path(@venue), notice: t('venues.coordinator_removed')
  end
end
