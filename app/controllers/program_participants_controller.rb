# frozen_string_literal: true

class ProgramParticipantsController < ApplicationController
  before_action :require_authentication
  before_action lambda {
    @program = Program.managed_by(current_user).find(params.expect(:program_id))
  }
  rescue_from BookingMutation::Invalid, with: :show_error

  def index
    @roster = ProgramRoster.new(@program, page: params[:page])
    @memberships = @roster.memberships
    @invitations = @program.participant_invitations.order_by(created_at: :desc)
  end

  def invite
    result = delivery.call(params.expect(:id))
    key = result == :failed ? 'email_failed' : result
    flash_key = result == :failed ? :alert : :notice
    redirect_to roster_path, flash_key => @program.message("participant_access.#{key}")
  end

  def invite_all
    results = @program.memberships.participants.map { |membership| delivery.call(membership.id) }.tally
    notice = @program.message('participant_access.bulk_result', sent: results.fetch(:sent, 0),
                                                                failed: results.fetch(:failed, 0),
                                                                skipped: results.fetch(:skipped, 0))
    redirect_to roster_path, notice: notice
  end

  def pause
    mutation.pause(params.expect(:id), params.permit(:reason)[:reason])
    redirect_to roster_path, notice: @program.message('participant_access.pause_saved')
  end

  def resume
    mutation.resume(params.expect(:id))
    redirect_to roster_path, notice: @program.message('participant_access.resumed')
  end

  private

  def roster_path
    program_participants_path(@program, page: params[:page])
  end

  def mutation
    ParticipantAccessMutation.new(program: @program, user: current_user)
  end

  def delivery
    BookingInvitationDelivery.new(program: @program, user: current_user)
  end

  def show_error(error)
    redirect_to roster_path, alert: error.message
  end
end
