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
    coordinator_token = params[:coordinator_invitation_token]
    invitation_token = params[:invitation_token]
    reset_session
    return redirect_to coordinator_invitation_path(token: coordinator_token), status: :see_other if coordinator_token

    redirect_to(invitation_token ? invitation_path(token: invitation_token) : new_session_path, status: :see_other)
  end

  private

  def finish_sign_in(user)
    invitation_token = session[:invitation_token]
    coordinator_token = session[:coordinator_invitation_token]
    booking_program = session[:booking_program]
    start_session(user, remember_me: params[:remember_me] == '1')
    return redirect_to coordinator_invitation_path(token: coordinator_token) if coordinator_token

    redirect_to(invitation_token ? invitation_path(token: invitation_token) : booking_return_path(
      booking_program, user
    ))
  end

  def booking_return_path(id, user)
    id ? program_path(Program.visible_to(user).find(id)) : root_path
  rescue Mongoid::Errors::DocumentNotFound
    root_path
  end
end
