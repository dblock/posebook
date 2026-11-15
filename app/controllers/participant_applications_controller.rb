# frozen_string_literal: true

class ParticipantApplicationsController < ApplicationController
  include ParticipantApplicationErrors

  before_action -> { response.headers['Cache-Control'] = 'private, no-store' }
  before_action :remember_status_destination, only: :show
  before_action :require_authentication, except: %i[new create apply]
  before_action :find_program, except: :index
  before_action :require_verified_applicant, only: %i[new create apply]
  before_action :prepare_submission, only: %i[new create apply]

  def index
    @page = [params[:page].to_i, 1].max
    @applications = ParticipantApplication.where(user_id: current_user.id).includes(:program)
                                          .order_by(created_at: :desc, id: :desc).skip((@page - 1) * 50).limit(51).to_a
    @more = @applications.length > 50
    @applications = @applications.first(50)
  end

  def show
    @application = own_application
    redirect_to new_program_participation_application_path(@program) if @application.draft?
  end

  def apply
    redirect_to new_program_participation_application_path(@program)
  end

  def new
    return if @application

    @application = ParticipantApplication.new(status: 'draft')
  end

  def create
    attributes = editor_attributes
    @application = save_editor(attributes)
    if attributes[:intent] == 'draft' || attributes[:remove_photo_id].present?
      redirect_to new_program_participation_application_path(@program),
                  notice: t('participant_applications.draft_saved')
    else
      submit_editor(attributes)
    end
  end

  def destroy
    return abandon_draft if own_application.draft?

    workflow.withdraw(own_application.id, version: params[:lock_version])
    redirect_to own_application_path, notice: t('participant_applications.withdrawn')
  end

  private

  def save_editor(attributes)
    draft.save(**attributes.slice(:message, :profile, :photos, :remove_photo_id).to_h.symbolize_keys,
                version: attributes[:lock_version])
  end

  def submit_editor(attributes)
    workflow.submit(message: @application.message, consent: attributes[:consent], version: @application.lock_version)
    redirect_to own_application_path, notice: t('participant_applications.submitted')
  end

  def abandon_draft
    draft.discard(version: params[:lock_version])
    redirect_to program_path(@program), notice: t('participant_applications.draft_abandoned')
  end

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
    @application = ParticipantApplication.where(program_id: @program.id, user_id: current_user.id).first
    return redirect_to own_application_path if @application && !@application.draft?

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

  def draft
    ApplicationDraft.new(program: @program, user: current_user)
  end

  def editor_attributes
    params.expect(participant_application: [:message, :consent, :lock_version, :intent, :remove_photo_id,
                                            { profile: ApplicationDraft::PROFILE_FIELDS, photos: [] }])
  end
end
