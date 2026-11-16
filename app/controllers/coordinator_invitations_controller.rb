# frozen_string_literal: true

class CoordinatorInvitationsController < ApplicationController
  before_action :require_authentication
  before_action :find_target
  before_action :find_invitation

  def show
    link = flash[:invitation_link]
    flash.delete(:invitation_link)
    @token = link['token'] if link && link['id'] == @invitation.id.to_s
  end

  def destroy
    result = @invitation.revoke
    redirect_to new_polymorphic_path([@target, :coordinator]),
                result ? { notice: t('invitations.revoked') } : { alert: t('invitations.not_pending') }
  end

  private

  def find_target
    if params[:venue_id]
      @target = Venue.find(params.expect(:venue_id))
      head :forbidden unless current_user.system_admin?
    else
      @target = Program.find(params.expect(:program_id))
      head :forbidden unless @target.venue.coordinated_by?(current_user)
    end
  end

  def find_invitation
    scope = @target.is_a?(Venue) ? { venue_id: @target.id, program_id: nil } : { program_id: @target.id, venue_id: nil }
    @invitation = CoordinatorInvitation.where(scope).find(params.expect(:id))
  end
end
