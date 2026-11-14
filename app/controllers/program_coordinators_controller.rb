# frozen_string_literal: true

class ProgramCoordinatorsController < ApplicationController
  before_action :require_authentication
  before_action :find_program

  def index
    @organizers = @program.memberships.coordinators.includes(:user).to_a
  end

  def create
    user = eligible_user
    unless user
      return redirect_to program_coordinators_path(@program),
                         alert: t('venues.coordinator_not_found')
    end

    ProgramMembership.grant_coordinator_access(@program, user)
    redirect_to program_coordinators_path(@program), notice: @program.message('programs.organizer_added')
  end

  def destroy
    membership = @program.memberships.coordinators.find(params.expect(:id))
    membership.revoke_coordinator_access
    redirect_to program_coordinators_path(@program), notice: @program.message('programs.organizer_removed')
  end

  private

  def eligible_user
    return User.active.find(params.expect(:user_id)) if params[:user_id]

    User.active.where(email: params.expect(:email).to_s.strip.downcase).first
  end

  def find_program
    @program = Program.find(params.expect(:program_id))
    head :forbidden unless @program.venue.coordinated_by?(current_user)
  end
end
