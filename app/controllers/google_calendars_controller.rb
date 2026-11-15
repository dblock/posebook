# frozen_string_literal: true

class GoogleCalendarsController < ApplicationController
  before_action :require_authentication
  before_action :find_program

  def show
    @connection = GoogleCalendarConnection.where(program_id: @program.id).first
    @pending_count = GoogleCalendarSync.where(program_id: @program.id, :due_at.ne => nil).count
  end

  def create
    attributes = params.expect(google_calendar: %i[calendar_id private_calendar])
    calendar_id = attributes[:calendar_id].to_s.strip
    error = connection_error(calendar_id, attributes[:private_calendar])
    return redirect_to program_google_calendar_path(@program), alert: t("google_calendar.#{error}") if error

    authorize_calendar(calendar_id)
  end

  def destroy
    connection = GoogleCalendarConnection.where(program_id: @program.id).first
    connection&.update!(enabled: false, encrypted_refresh_token: nil)
    redirect_to program_google_calendar_path(@program), notice: t('google_calendar.disconnected')
  end

  private

  def connection_error(calendar_id, confirmed)
    return 'unavailable' unless GoogleCalendarConnection.configured?
    return 'private_required' unless confirmed == '1' && calendar_id.present? && calendar_id.length <= 254

    connection = GoogleCalendarConnection.where(program_id: @program.id, enabled: true).first
    'disconnect_first' if connection && connection.calendar_id != calendar_id
  end

  def authorize_calendar(calendar_id)
    state = SecureRandom.hex(32)
    session[:google_calendar_oauth] = {
      state: state, program_id: @program.id.to_s, user_id: current_user.id.to_s,
      calendar_id: calendar_id, expires_at: 10.minutes.from_now.to_i
    }
    url = GoogleCalendarConnection.credentials.authorization_uri(
      access_type: 'offline', prompt: 'consent', state: state
    )
    redirect_to url.to_s, allow_other_host: true
  end

  def find_program
    @program = Program.managed_by(current_user).find(params.expect(:program_id))
  end
end
