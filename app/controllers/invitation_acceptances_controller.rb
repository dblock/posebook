# frozen_string_literal: true

class InvitationAcceptancesController < ApplicationController
  before_action :find_invitation
  rate_limit to: 5, within: 5.minutes, only: %i[create register]
  rescue_from Mongo::Error::OperationFailure, with: :handle_database_error

  def show
    session[:invitation_token] = @token
    @user = User.new
  end

  def create
    return redirect_to new_session_path unless current_user

    @acceptance = InvitationAcceptance.new(token: @token, user: current_user)
    finish_acceptance
  rescue InvitationAcceptance::Unavailable
    render :unavailable, status: :gone
  end

  def register
    return redirect_to invitation_path(token: @token) if current_user

    attributes = params.expect(user: %i[name email phone password password_confirmation]).to_h.symbolize_keys
    @acceptance = InvitationAcceptance.new(token: @token, attributes: attributes)
    finish_acceptance
  rescue Mongoid::Errors::Validations
    @user = @acceptance.user
    render :show, status: :unprocessable_content
  rescue InvitationAcceptance::Unavailable
    render :unavailable, status: :gone
  end

  private

  def find_invitation
    @token = params[:token]
    @invitation = ModelInvitation.available(@token)
    render :unavailable, status: :gone unless @invitation
  end

  def finish_acceptance
    @user = @acceptance.call
    start_session(@user)
    redirect_to venue_path(@invitation.venue_id), notice: t('invitations.accepted')
  end

  def handle_database_error(error)
    raise error unless error.code == 11_000

    @user = @acceptance.user
    flash.now[:alert] = t('invitations.conflict')
    render :show, status: :conflict
  end
end
