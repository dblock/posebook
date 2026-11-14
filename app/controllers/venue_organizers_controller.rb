# frozen_string_literal: true

class VenueOrganizersController < ApplicationController
  before_action :require_authentication
  before_action :require_system_admin
  before_action -> { @venue = Venue.find(params.expect(:venue_id)) }

  def index
    @organizers = @venue.memberships.schedule_managers.includes(:user).to_a
    @eligible_users = User.active.where(:id.nin => @organizers.map(&:user_id)).order_by(name: :asc)
  end

  def create
    user = User.active.find(params.expect(:user_id))
    VenueMembership.grant_schedule_access(@venue, user)
    redirect_to venue_organizers_path(@venue), notice: t('venues.organizer_added')
  end

  def destroy
    membership = @venue.memberships.find(params.expect(:id))
    membership.revoke_schedule_access
    redirect_to venue_organizers_path(@venue), notice: t('venues.organizer_removed')
  end
end
