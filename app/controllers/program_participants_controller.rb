# frozen_string_literal: true

class ProgramParticipantsController < ApplicationController
  before_action :require_authentication
  before_action lambda {
    response.headers['Cache-Control'] = 'private, no-store'
    @program = Program.managed_by(current_user).find(params.expect(:program_id))
  }
  rescue_from BookingMutation::Invalid, with: :show_error

  def index
    status = params[:status].presence || 'all'
    return head :bad_request unless ProgramRoster::STATUSES.include?(status)

    @roster = ProgramRoster.new(@program, cursor: params[:cursor], status: status)
    @memberships = @roster.memberships
  end

  def edit
    @membership = @program.memberships.participants.find(params.expect(:id))
    @participant = @membership.user
  end

  def update
    @membership = ParticipantDetailsUpdate.new(program: @program, user: current_user)
                                          .call(params.expect(:id), participant_params)
    @participant = @membership.user
    if @membership.errors.empty?
      redirect_to roster_path, notice: @program.message('participant_access.details_updated')
    else
      render_invalid_details
    end
  end

  def invite
    result = delivery.call(params.expect(:id))
    key = result == :failed ? 'email_failed' : result
    flash_key = result == :failed ? :alert : :notice
    redirect_to roster_path, flash_key => @program.message("participant_access.#{key}")
  end

  def invite_all
    results = @program.memberships.participants.map { |membership| delivery.call(membership.id) }.tally
    notice = @program.message('participant_access.bulk_result', queued: results.fetch(:queued, 0),
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

  def render_invalid_details
    render :edit, status: :unprocessable_content
  end

  def participant_params
    params.expect(participant: %i[display_name instagram_hidden photos_hidden notes]).to_h.symbolize_keys
  end

  def roster_path
    program_participants_path(@program, cursor: params[:cursor], status: params[:status])
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
