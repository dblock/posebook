# frozen_string_literal: true

class CoordinatorInvitationAcceptancesController < InvitationAcceptancesController
  def show
    super
    @user.assign_attributes(name: @invitation.name, email: @invitation.email)
  end

  private

  def invitation_class
    CoordinatorInvitation
  end

  def invitation_session_key
    :coordinator_invitation_token
  end

  def acceptance_path
    coordinator_invitation_path(token: @token)
  end

  def accepted_location
    polymorphic_path(@invitation.target)
  end

  def acceptance_notice
    t('coordinator_invitations.accepted', name: @invitation.target.name)
  end
end
