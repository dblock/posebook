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

    application_return_path(user) || booking_return_path(session[:booking_program], user)
  end

  def sign_out_destination
    if params[:coordinator_invitation_token]
      return coordinator_invitation_path(token: params[:coordinator_invitation_token])
    end
    return invitation_path(token: params[:invitation_token]) if params[:invitation_token]

    token = params[:application_registration_token]
    token ? application_verification_path(token: token) : new_session_path
  end

  def booking_return_path(id, user)
    id ? program_path(Program.visible_to(user).find(id), section: 'calendar') : root_path
  rescue Mongoid::Errors::DocumentNotFound
    root_path
  end

  def application_return_path(user)
    session[:application_review] ? application_review_path(user) : applicant_return_path
  rescue Mongoid::Errors::DocumentNotFound
    root_path
  end

  def application_review_path(user)
    destination = session[:application_review]
    program = Program.managed_by(user).find(destination['program'])
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
