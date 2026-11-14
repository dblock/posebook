# frozen_string_literal: true

class ApplicationController < ActionController::Base
  helper_method :current_user

  private

  def current_user
    return unless session[:user_id]

    @current_user ||= User.active.where(id: session[:user_id],
                                        session_version: session[:session_version]).first
  end

  def require_authentication
    return if current_user

    redirect_to(User.exists? ? new_session_path : new_registration_path)
  end

  def start_session(user)
    reset_session
    session[:user_id] = user.id.to_s
    session[:session_version] = user.session_version
  end

  def require_system_admin
    head :forbidden unless current_user.system_admin?
  end
end
