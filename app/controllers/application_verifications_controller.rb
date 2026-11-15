# frozen_string_literal: true

class ApplicationVerificationsController < InvitationAcceptancesController
  before_action -> { response.headers['Cache-Control'] = 'private, no-store' }

  private

  def invitation_class
    ApplicationRegistration
  end

  def invitation_session_key
    :application_registration_token
  end

  def acceptance_path
    application_verification_path(token: @token)
  end

  def accepted_location
    new_program_participation_application_path(@program)
  end

  def acceptance_notice
    t('application_registration.verified')
  end

  def handle_recipient_mismatch
    @user = @acceptance.user
    @user.email = @invitation.email if @user.new_record?
    @user.errors.add(:email, 'must match the address on this verification link.')
    render :show, status: @user.persisted? ? :forbidden : :unprocessable_content
  end
end
