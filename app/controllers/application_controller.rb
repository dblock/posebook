# frozen_string_literal: true

class ApplicationController < ActionController::Base
  REMEMBER_COOKIE = :_posebook_remember_me

  helper_method :current_user, :profile_tab_enabled?
  around_action :with_remembered_login
  around_action :with_history_actor

  private

  def with_history_actor(&)
    Current.set(user: current_user, &)
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = session_user || remembered_user
  end

  def profile_tab_enabled?(tab, user)
    case tab
    when 'bookings' then ProgramMembership.participants.exists?(user_id: user.id)
    when 'history' then Booking.exists?(user_id: user.id)
    when 'applications' then ParticipantApplication.exists?(user_id: user.id)
    when 'programs' then Program.managed_by(user).exists?
    else true
    end
  end

  def participant_dashboard
    @participant_dashboard ||= ParticipantDashboard.new(current_user)
  end

  def session_user
    return unless session[:user_id]

    User.active.where(id: session[:user_id], session_version: session[:session_version]).first
  end

  def remembered_user
    credentials = cookies.encrypted[REMEMBER_COOKIE]
    return unless credentials.is_a?(Hash)

    user = User.active.where(id: credentials['user_id'], session_version: credentials['session_version']).first
    start_session(user, remember_me: true) if user
    user
  end

  def require_authentication
    return if current_user

    redirect_to(User.exists? ? new_session_path : new_registration_path)
  end

  def start_session(user, remember_me: false)
    reset_session
    session[:user_id] = user.id.to_s
    session[:session_version] = user.session_version
    session[:remember_me] = true if remember_me
    @current_user = user
  end

  def with_remembered_login
    yield
  ensure
    if session[:remember_me] && current_user
      remember_user(current_user)
    elsif cookies[REMEMBER_COOKIE]
      cookies.delete(REMEMBER_COOKIE)
    end
  end

  def remember_user(user)
    options = { httponly: true, same_site: :lax, secure: request.ssl? }
    cookies.encrypted[REMEMBER_COOKIE] = options.merge(
      value: { user_id: user.id.to_s, session_version: user.session_version }
    )
    # Browser storage has a renewable lifetime; the encrypted credential has no application deadline.
    cookies[REMEMBER_COOKIE] = options.merge(value: cookies[REMEMBER_COOKIE], expires: 20.years.from_now)
  end

  def require_system_admin
    head :forbidden unless current_user.system_admin?
  end
end
