# frozen_string_literal: true

require 'net/smtp'

module CoordinatorInviting
  extend ActiveSupport::Concern

  included do
    before_action :prepare_coordinator_page, only: %i[index create]
  end

  def index; end

  def create
    @invitation.assign_attributes(name: params[:name], email: invitee_email, invited_by: current_user)
    return render :index, status: :unprocessable_content unless @invitation.valid?

    @existing_user = User.where(email: @invitation.email).first
    return handle_existing_user if @existing_user
    return invitation_error('coordinator_invitations.account_changed') if params[:grant_access] == '1'

    finish_invitation
  end

  private

  def finish_invitation
    return invitation_error('invitations.delivery_unavailable') unless delivery_available?

    @invitation.save!
    deliver_invitation
    flash[:invitation_link] = { 'id' => @invitation.id.to_s, 'token' => @invitation.token }
    redirect_to polymorphic_path([@invitation.target, @invitation]), notice: t('invitations.created')
  end

  def prepare_coordinator_page
    @invitation = CoordinatorInvitation.new(venue: @venue, program: @program)
    @coordinators = @invitation.target.memberships.coordinators.includes(:user).to_a
    @invitations = CoordinatorInvitation.where(venue_id: @venue&.id, program_id: @program&.id)
                                        .order_by(created_at: :desc)
  end

  def invitee_email
    params[:user_id] ? User.active.find(params.expect(:user_id)).email : params.expect(:email)
  end

  def handle_existing_user
    return invitation_error('coordinator_invitations.inactive') unless @existing_user.active?
    return render :index unless params[:grant_access] == '1' || params[:user_id]

    @invitation.grant_access(@existing_user)
    redirect_to polymorphic_path([@invitation.target, :coordinators]),
                notice: t('coordinator_invitations.granted', role: @invitation.coordinator_label)
  end

  def invitation_error(key)
    @invitation.errors.add(:base, t(key))
    render :index, status: :unprocessable_content
  end

  def delivery_available?
    params[:send_email] != '1' || Rails.configuration.x.password_reset_delivery_enabled
  end

  def deliver_invitation
    return unless params[:send_email] == '1'

    CoordinatorInvitationMailer.invite(@invitation, @invitation.token).deliver_now
  rescue IOError, SystemCallError, Timeout::Error, Net::SMTPError => e
    NewRelic::Agent.notice_error(e)
    flash[:alert] = t('invitations.delivery_failed')
  end
end
