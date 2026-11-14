# frozen_string_literal: true

require 'net/smtp'

class ProgramInvitationsController < ApplicationController
  before_action :require_authentication
  before_action lambda {
    @program = Program.managed_by(current_user).find(params.expect(:program_id))
  }
  before_action :find_invitation, only: %i[show destroy]

  def show
    link = flash[:invitation_link]
    flash.delete(:invitation_link)
    @token = link['token'] if link && link['id'] == @invitation.id.to_s
  end

  def new
    @invitation = @program.participant_invitations.new
  end

  def create
    @invitation = @program.participant_invitations.new(params.expect(participant_invitation: %i[name email]))
    @invitation.invited_by = current_user
    if delivery_available? && @invitation.save
      finish_creation
    else
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    result = @invitation.revoke
    redirect_to @program,
                result ? { notice: t('invitations.revoked') } : { alert: t('invitations.not_pending') }
  end

  private

  def finish_creation
    deliver_invitation
    flash[:invitation_link] = { 'id' => @invitation.id.to_s, 'token' => @invitation.token }
    redirect_to program_participant_invitation_path(@program, @invitation), notice: t('invitations.created')
  end

  def find_invitation
    @invitation = @program.participant_invitations.find(params.expect(:id))
  end

  def delivery_available?
    return true unless params[:send_email] == '1'
    return true if @invitation.email.present? && Rails.configuration.x.password_reset_delivery_enabled

    @invitation.errors.add(:base, t('invitations.delivery_unavailable'))
    false
  end

  def deliver_invitation
    return unless params[:send_email] == '1'

    ParticipantInvitationMailer.invite(@invitation, @invitation.token).deliver_now
  rescue IOError, SystemCallError, Timeout::Error, Net::SMTPError => e
    NewRelic::Agent.notice_error(e)
    flash[:alert] = t('invitations.delivery_failed')
  end
end
