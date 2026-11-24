# frozen_string_literal: true

class SessionsController < ApplicationController
  rate_limit to: 10, within: 5.minutes, only: :create

  def new; end

  def create
    user = User.with_email(params[:email])
    if user&.authenticate(params[:password].to_s)
      finish_sign_in(user)
    else
      flash.now[:alert] = t('accounts.invalid_credentials')
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    destination = sign_out_destination
    reset_session
    redirect_to destination, status: :see_other
  end

  private

  def finish_sign_in(user)
    destination = sign_in_destination(user)
    start_session(user, remember_me: params[:remember_me] == '1')
    redirect_to destination
  end

  def sign_in_destination(user)
    coordinator = session[:coordinator_invitation_token]
    invitation = session[:invitation_token]
    registration = session[:application_registration_token]
    return coordinator_invitation_path(token: coordinator) if coordinator
    return invitation_path(token: invitation) if invitation
    return application_verification_path(token: registration) if registration

    booking_page_path || application_return_path(user) || booking_return_path(session[:booking_program], user)
  end

  def coordinator_return_path(user)
    return if user.system_admin?

    program = Program.managed_by(user).order_by(name: :asc).first
    return program_path(program) if program

    programs_profile_path if Venue.coordinated_by(user).exists?
  end

  def sign_out_destination
    if params[:coordinator_invitation_token]
      return coordinator_invitation_path(token: params[:coordinator_invitation_token])
    end
    return invitation_path(token: params[:invitation_token]) if params[:invitation_token]

    token = params[:application_registration_token]
    token ? application_verification_path(token: token) : new_session_path
  end

  # Returns to a booking linked from an email; the booking page itself enforces access.
  def booking_page_path
    program_id, booking_id = session.delete(:booking_page)
    program_booking_path(program_id, booking_id) if program_id.present? && booking_id.present?
  rescue ActionController::UrlGenerationError
    nil
  end

  def booking_return_path(id, user)
    return coordinator_return_path(user) || root_path unless id

    calendar_program_path(Program.visible_to(user).find(id))
  rescue Mongoid::Errors::DocumentNotFound
    root_path
  end

  def application_return_path(user)
    return application_status_path(user) if session[:application_status]

    session[:application_review] ? application_review_path(user) : applicant_return_path
  rescue Mongoid::Errors::DocumentNotFound
    root_path
  end

  def application_status_path(user)
    program = Program.find(session[:application_status])
    return root_path unless ParticipantApplication.exists?(program_id: program.id, user_id: user.id)

    program_participation_application_path(program)
  end

  def application_review_path(user)
    destination = session[:application_review]
    program = Program.managed_by(user).find(destination['program'])
    return history_program_applications_path(program) if destination['history']
    return program_applications_path(program) unless destination['application']

    application = ParticipantApplication.where(program_id: program.id).find(destination['application'])
    program_application_path(program, application)
  end

  def applicant_return_path
    return unless session[:application_program]

    program = Program.find(session[:application_program])
    new_program_participation_application_path(program) if program.booking_active? && program.applications_enabled?
  end
end
