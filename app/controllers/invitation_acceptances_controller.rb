# frozen_string_literal: true

class InvitationAcceptancesController < ApplicationController
  before_action :find_invitation
  rate_limit to: 5, within: 5.minutes, only: %i[create register]
  rescue_from Mongo::Error::OperationFailure, with: :handle_database_error
  rescue_from InvitationAcceptance::RecipientMismatch, with: :handle_recipient_mismatch
  rescue_from EmailDelivery::Unavailable, with: :handle_notification_error

  def show
    session.delete(:invitation_token)
    session.delete(:coordinator_invitation_token)
    session.delete(:application_registration_token)
    session[invitation_session_key] = @token
    @user = User.new(name: @invitation.name, email: @invitation.email, instagram_tagging_allowed: true)
  end

  def create
    return redirect_to new_session_path unless current_user

    @acceptance = InvitationAcceptance.new(token: @token, user: current_user, invitation_class: invitation_class)
    finish_acceptance
  rescue InvitationAcceptance::Unavailable
    render :unavailable, status: :gone
  end

  def register
    return redirect_to acceptance_path if current_user

    @acceptance = InvitationAcceptance.new(token: @token, attributes: registration_attributes,
                                           invitation_class: invitation_class)
    finish_acceptance
  rescue Mongoid::Errors::Validations
    @user = @acceptance.user
    render :show, status: :unprocessable_content
  rescue InvitationAcceptance::Unavailable
    render :unavailable, status: :gone
  end

  private

  def registration_attributes
    params.expect(user: %i[name email phone gender password password_confirmation
                           display_name instagram_handle instagram_tagging_allowed
                           public_profile_private]).to_h.symbolize_keys
  end

  def handle_notification_error
    @user = current_user || User.new(registration_attributes.except(:password, :password_confirmation))
    flash.now[:alert] = t('invitations.notifications_unavailable')
    render :show, status: :service_unavailable
  end

  def invitation_class
    ParticipantInvitation
  end

  def invitation_session_key
    :invitation_token
  end

  def acceptance_path
    invitation_path(token: @token)
  end

  def accepted_location
    program_path(@program, section: 'calendar')
  end

  def acceptance_notice
    @program.message('invitations.accepted')
  end

  def find_invitation
    @token = params[:token]
    @invitation = invitation_class.available(@token)
    @program = @invitation&.program
    render :unavailable, status: :gone unless @invitation
  end

  def finish_acceptance
    @user = @acceptance.call
    start_session(@user, remember_me: current_user == @user && session[:remember_me])
    redirect_to accepted_location, notice: acceptance_notice
  end

  def handle_database_error(error)
    raise error unless error.code == 11_000

    @user = @acceptance.user
    flash.now[:alert] = t('invitations.conflict')
    render :show, status: :conflict
  end

  def handle_recipient_mismatch
    @user = @acceptance.user
    @user.email = @invitation.email if @user.new_record?
    @user.errors.add(:email, t('invitations.email_mismatch'))
    flash.now[:alert] = t('invitations.wrong_account', email: @invitation.email)
    render :show, status: @user.persisted? ? :forbidden : :unprocessable_content
  end
end
