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
    @applications = page_of(records)
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
    redirect_to program_application_path(@program, params[:id]), notice: t('participant_applications.reviewed')
  end

  def history
    @events = page_of(ParticipationEvent.where(program_id: @program.id).includes(:actor))
    ids = @events.map(&:source_id)
    @sources = ParticipantApplication.where(:id.in => ids).index_by(&:id)
                                     .merge(ParticipantInvitation.where(:id.in => ids).index_by(&:id))
  end

  private

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
    @page = [params[:page].to_i, 1].max
    results = records.order_by(created_at: :desc, id: :desc).skip((@page - 1) * 50).limit(51).to_a
    @more = results.length > 50
    results.first(50)
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
