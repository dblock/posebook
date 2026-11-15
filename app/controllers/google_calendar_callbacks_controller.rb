# frozen_string_literal: true

class GoogleCalendarCallbacksController < ApplicationController
  before_action :require_authentication

  def show
    pending = session.delete(:google_calendar_oauth)&.with_indifferent_access
    return head :forbidden unless valid_state?(pending)

    @program = Program.managed_by(current_user).find(pending[:program_id])
    return failure if authorization_failed?

    complete_connection(pending)
  rescue Google::Apis::Error, Signet::AuthorizationError, Signet::RemoteServerError
    failure
  end

  private

  def authorization_failed?
    params[:error].present? || params[:code].blank?
  end

  def complete_connection(pending)
    auth = exchange_code
    calendar = GoogleCalendarConnection.service(auth).get_calendar_list(pending[:calendar_id])
    return failure unless %w[owner writer].include?(calendar.access_role) && auth.refresh_token.present?

    save_connection(pending[:calendar_id], auth.refresh_token)
    GoogleCalendarSync.reconcile
    redirect_to program_google_calendar_path(@program), notice: t('google_calendar.configured')
  end

  def exchange_code
    GoogleCalendarConnection.credentials.tap do |auth|
      auth.code = params[:code]
      auth.fetch_access_token!
    end
  end

  def save_connection(calendar_id, token)
    connection = GoogleCalendarConnection.find_or_initialize_by(program_id: @program.id)
    connection.assign_attributes(calendar_id: calendar_id, connected_by: current_user, enabled: true)
    connection.refresh_token = token
    connection.save!
  end

  def valid_state?(pending)
    pending && pending[:user_id] == current_user.id.to_s && pending[:expires_at].to_i > Time.current.to_i &&
      ActiveSupport::SecurityUtils.secure_compare(pending[:state].to_s, params[:state].to_s)
  end

  def failure
    redirect_to program_google_calendar_path(@program), alert: t('google_calendar.failed')
  end
end
