# frozen_string_literal: true

class ProgramCoordinatorsController < ApplicationController
  before_action :require_authentication
  before_action :find_program
  include CoordinatorInviting

  def destroy
    membership = @program.memberships.coordinators.find(params.expect(:id))
    membership.revoke_coordinator_access
    redirect_to program_coordinators_path(@program), notice: @program.message('programs.organizer_removed')
  end

  private

  def find_program
    @program = Program.find(params.expect(:program_id))
    head :forbidden unless @program.venue.coordinated_by?(current_user)
  end
end
