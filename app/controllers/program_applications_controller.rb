# frozen_string_literal: true

class ProgramApplicationsController < ApplicationController
  before_action :remember_review_destination
  before_action :require_authentication
  before_action :find_program
  rescue_from ParticipantApplicationWorkflow::Invalid, ParticipantApplicationWorkflow::Conflict, with: :decision_error
  rescue_from Mongoid::Errors::Validations, with: :validation_error
  rescue_from EmailDelivery::Unavailable, with: :notification_error

  def index
    @status = params[:status].presence || 'pending'
    return head :bad_request unless %w[pending declined accepted withdrawn all].include?(@status)

    records = ParticipantApplication.where(program_id: @program.id, :status.ne => 'draft')
    records = records.where(status: @status) unless @status == 'all'
    @applications = page_of(records.includes(:user))
  end

  def show
    @application = scoped_application
  end

  def update
    attributes = params.expect(participant_application: %i[status lock_version notes])
    ParticipantApplicationWorkflow.new(program: @program, user: current_user)
                                  .review(params.expect(:id), status: attributes[:status],
                                                              version: attributes[:lock_version],
                                                              notes: attributes[:notes])
    redirect_to review_destination(attributes[:status]), notice: t('participant_applications.reviewed')
  end

  def history
    @event = params[:event].presence || 'all'
    return head :bad_request unless @event == 'all' || ParticipationEvent::REVIEW_ACTIONS.include?(@event)

    @events = page_of(history_scope)
    @sources = history_sources
    @invitees = history_invitees
  end

  private

  def history_scope
    records = ParticipationEvent.reviewable.where(program_id: @program.id)
    records = records.where(action: @event) unless @event == 'all'
    records.includes(:actor)
  end

  def history_sources
    ids = @events.map(&:source_id)
    ParticipantApplication.where(program_id: @program.id, :id.in => ids).includes(:user).index_by(&:id)
                          .merge(ParticipantInvitation.where(program_id: @program.id, :id.in => ids).index_by(&:id))
  end

  def history_invitees
    ids = @sources.values.grep(ParticipantInvitation).filter_map do |invitation|
      invitation.used_by_id if invitation.used_at
    end
    User.where(:id.in => ids).index_by(&:id)
  end

  def review_destination(status)
    return program_applications_path(@program) if status == 'declined'

    program_application_path(@program, params[:id])
  end

  def remember_review_destination
    return if current_user

    session[:application_review] = { program: params[:program_id], application: params[:id],
                                     history: action_name == 'history' }
    session.delete(:application_status)
    session.delete(:application_program)
  end

  def notification_error
    decision_error(EmailDelivery::Unavailable.new(t('participant_applications.notifications_unavailable')))
  end

  def find_program
    response.headers['Cache-Control'] = 'private, no-store'
    @program = Program.managed_by(current_user).find(params.expect(:program_id))
  end

  def scoped_application
    ParticipantApplication.where(program_id: @program.id, :status.ne => 'draft').find(params.expect(:id))
  end

  def page_of(records)
    @pagination = CursorPage.new(records.order_by(created_at: :desc), cursor: params[:cursor])
    @pagination.records
  end

  def decision_error(error)
    scoped_application
    redirect_to program_application_path(@program, params[:id]), alert: error.message
  end

  def validation_error(error)
    scoped_application
    redirect_to program_application_path(@program, params[:id]), alert: error.document.errors.full_messages.to_sentence
  end
end
