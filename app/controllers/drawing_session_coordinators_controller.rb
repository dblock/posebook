# frozen_string_literal: true

class DrawingSessionCoordinatorsController < ApplicationController
  before_action :require_authentication
  before_action :find_drawing_session

  def index
    @organizers = @drawing_session.memberships.coordinators.includes(:user).to_a
  end

  def create
    user = eligible_user
    unless user
      return redirect_to drawing_session_coordinators_path(@drawing_session),
                         alert: t('venues.coordinator_not_found')
    end

    DrawingSessionMembership.grant_coordinator_access(@drawing_session, user)
    redirect_to drawing_session_coordinators_path(@drawing_session), notice: t('drawing_sessions.organizer_added')
  end

  def destroy
    membership = @drawing_session.memberships.coordinators.find(params.expect(:id))
    membership.revoke_coordinator_access
    redirect_to drawing_session_coordinators_path(@drawing_session), notice: t('drawing_sessions.organizer_removed')
  end

  private

  def eligible_user
    return User.active.find(params.expect(:user_id)) if params[:user_id]

    User.active.where(email: params.expect(:email).to_s.strip.downcase).first
  end

  def find_drawing_session
    @drawing_session = DrawingSession.find(params.expect(:drawing_session_id))
    head :forbidden unless @drawing_session.venue.coordinated_by?(current_user)
  end
end
