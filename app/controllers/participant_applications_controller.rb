# frozen_string_literal: true

class ParticipantApplicationsController < ApplicationController
  before_action -> { response.headers['Cache-Control'] = 'private, no-store' }
  before_action :remember_status_destination, only: :show
  before_action :require_authentication, except: %i[new create]
  before_action :find_program, except: :index
  before_action :require_verified_applicant, only: %i[new create]
  before_action :prepare_submission, only: %i[new create]
  rescue_from ParticipantApplicationWorkflow::Invalid, with: :submission_error
  rescue_from ParticipantApplicationWorkflow::Conflict, with: :withdrawal_error
  rescue_from Mongoid::Errors::Validations, with: :validation_error
  rescue_from Mongo::Error::OperationFailure, with: :duplicate_application
  rescue_from EmailDelivery::Unavailable, with: :notification_error

  def index
    @page = [params[:page].to_i, 1].max
    @applications = ParticipantApplication.where(user_id: current_user.id).includes(:program)
                                          .order_by(created_at: :desc, id: :desc).skip((@page - 1) * 50).limit(51).to_a
    @more = @applications.length > 50
    @applications = @applications.first(50)
  end

  def show
    @application = own_application
  end

  def new
    @application = ParticipantApplication.new
  end

  def create
    attributes = params.expect(participant_application: %i[message consent])
    workflow.submit(message: attributes[:message], consent: attributes[:consent])
    redirect_to own_application_path, notice: t('participant_applications.submitted')
  end

  def destroy
    workflow.withdraw(own_application.id, version: params[:lock_version])
    redirect_to own_application_path, notice: t('participant_applications.withdrawn')
  end

  private

  def remember_status_destination
    return if current_user

    session[:application_status] = params[:program_id]
    session.delete(:application_review)
    session.delete(:application_program)
  end

  def find_program
    @program = Program.find(params.expect(:program_id))
  end

  def prepare_submission
    return redirect_to own_application_path if ParticipantApplication.exists?(program_id: @program.id,
                                                                              user_id: current_user.id)

    redirect_to program_path(@program) if @program.participant?(current_user)
  end

  def require_verified_applicant
    return head :not_found unless @program.applications_enabled? && @program.booking_active?
    return if current_user&.email_verified_at

    session[:application_program] = @program.id.to_s unless current_user
    redirect_to new_program_application_registration_path(@program)
  end

  def own_application
    ParticipantApplication.where(program_id: @program.id, user_id: current_user.id).first!
  end

  def own_application_path
    program_participation_application_path(@program)
  end

  def workflow
    ParticipantApplicationWorkflow.new(program: @program, user: current_user)
  end

  def submission_error(error, status: :unprocessable_content)
    @application = ParticipantApplication.new(message: params.dig(:participant_application, :message))
    @application.errors.add(:base, error.message)
    render :new, status: status
  end

  def notification_error
    submission_error(EmailDelivery::Unavailable.new(t('participant_applications.notifications_unavailable')),
                     status: :service_unavailable)
  end

  def validation_error(error)
    raise error unless error.document.is_a?(ParticipantApplication)

    @application = error.document
    render :new, status: :unprocessable_content
  end

  def withdrawal_error(error)
    redirect_to own_application_path, alert: error.message
  end

  def duplicate_application(error)
    raise error unless error.code == 11_000

    redirect_to own_application_path, alert: t('participant_applications.duplicate')
  end
end
