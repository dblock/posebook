# frozen_string_literal: true

module ParticipantApplicationErrors
  extend ActiveSupport::Concern

  included do
    rescue_from ParticipantApplicationWorkflow::Invalid, ProfileImage::Invalid, with: :submission_error
    rescue_from ParticipantApplicationWorkflow::Conflict, with: :withdrawal_error
    rescue_from Mongoid::Errors::Validations, with: :validation_error
    rescue_from Mongo::Error::OperationFailure, with: :duplicate_application
    rescue_from EmailDelivery::Unavailable, with: :notification_error
  end

  private

  def submission_error(error, status: :unprocessable_content)
    @application = ParticipantApplication.where(program_id: @program.id, user_id: current_user.id).first ||
                   ParticipantApplication.new(message: params.dig(:participant_application, :message), status: 'draft')
    @application.errors.add(:base, error.message)
    render :new, status: status
  end

  def notification_error
    submission_error(EmailDelivery::Unavailable.new(t('participant_applications.draft_notifications_unavailable')),
                     status: :service_unavailable)
  end

  def validation_error(error)
    if error.document.is_a?(User)
      @profile = error.document
    elsif error.document.is_a?(ParticipantApplication)
      @application = error.document
    else
      raise error
    end
    render :new, status: :unprocessable_content
  end

  def withdrawal_error(error)
    destination = if ParticipantApplication.exists?(program_id: @program.id, user_id: current_user.id)
                    own_application_path
                  else
                    new_program_participation_application_path(@program)
                  end
    redirect_to destination, alert: error.message
  end

  def duplicate_application(error)
    raise error unless error.code == 11_000

    redirect_to own_application_path, alert: t('participant_applications.duplicate')
  end
end
