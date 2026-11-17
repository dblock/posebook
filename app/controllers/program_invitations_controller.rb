# frozen_string_literal: true

class ProgramInvitationsController < ApplicationController
  before_action :require_authentication
  before_action lambda {
    response.headers['Cache-Control'] = 'private, no-store'
    @program = Program.managed_by(current_user).find(params.expect(:program_id))
  }
  before_action :find_invitation, only: %i[show destroy]

  def index
    @status = params[:status].presence || 'all'
    return head :bad_request unless ParticipantInvitation::STATUSES.include?(@status)

    @pagination = CursorPage.new(invitation_scope, cursor: params[:cursor])
    @invitations = @pagination.records
    @invitees = accepted_invitees
  end

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
    if @invitation.save
      finish_creation
    else
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    result = @invitation.revoke
    redirect_to program_participant_invitations_path(@program, cursor: params[:cursor], status: params[:status]),
                result ? { notice: t('invitations.revoked') } : { alert: t('invitations.not_pending') }
  end

  private

  def invitation_scope
    @program.participant_invitations.with_status(@status).includes(:invited_by).order_by(created_at: :desc)
  end

  def accepted_invitees
    ids = @invitations.filter_map { |invitation| invitation.used_by_id if invitation.used_at }
    User.where(:id.in => ids).index_by(&:id)
  end

  def finish_creation
    queued = deliver_invitation
    flash[:invitation_link] = { 'id' => @invitation.id.to_s, 'token' => @invitation.token }
    redirect_to program_participant_invitation_path(@program, @invitation),
                notice: t(queued ? 'invitations.created_and_queued' : 'invitations.created')
  end

  def find_invitation
    @invitation = @program.participant_invitations.find(params.expect(:id))
  end

  def deliver_invitation
    return unless @invitation.email.present? && Rails.configuration.x.password_reset_delivery_enabled

    EmailDelivery.enqueue('participant_invitation', @invitation, token: @invitation.token,
                                                                 expires_at: @invitation.expires_at)
  rescue EmailDelivery::Unavailable => e
    NewRelic::Agent.notice_error(e)
    flash[:alert] = t('invitations.delivery_failed')
    false
  end
end
