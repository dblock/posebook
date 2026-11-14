# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Drawing schedules', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:drawing_session) { create_drawing_session }

  def save_day(**attributes)
    patch drawing_session_schedule_path(drawing_session), params: {
      schedule: { date: '2026-11-16', mode: 'open', start_time: '19:30', reason: 'Later start.' }.merge(attributes)
    }
    drawing_session.schedule_exceptions.each { |exception| track_record(exception) }
  end

  it 'lets an assigned coordinator manage exceptions and regular session settings' do
    organizer = create_user
    grant_coordinator_access(drawing_session, organizer)
    sign_in(organizer)
    get drawing_session_schedule_path(drawing_session, date: '2026-11-16')
    expect(response.body).to include('Drawing Schedule', 'Save Schedule')
    save_day
    expect(response).to redirect_to(drawing_session_path(drawing_session, month: '2026-11'))
    expect(drawing_session.schedule_exceptions.first.history_tracks.last.modifier_id).to eq(organizer.id)
    patch drawing_session_path(drawing_session), params: { drawing_session: { start_time: '20:30' } }
    expect(response).to redirect_to(drawing_session_path(drawing_session))
    expect(drawing_session.reload.start_time).to eq('20:30')
  end

  it 'does not expose schedule controls or allow writes by models or organizers from another drawing_session' do
    user = create_user
    grant_model_access(drawing_session, user)
    grant_coordinator_access(create_drawing_session, user)
    sign_in(user)
    get drawing_session_path(drawing_session)
    expect(response.body).not_to include('Manage Schedule', 'Edit Day')
    get drawing_session_schedule_path(drawing_session)
    expect(response).to have_http_status(:not_found)
    save_day
    expect(response).to have_http_status(:not_found)
    expect(drawing_session.schedule_exceptions).to be_empty
  end

  it 'renders calendar times, one-off openings, holiday reasons, and manager edit links' do
    sign_in(create_user(roles: ['system_admin']))
    save_day(date: '2026-11-17', start_time: '14:00', reason: 'Extra drawing.')
    save_day(date: '2026-11-23', mode: 'closed', reason: 'Holiday closure.')
    get drawing_session_path(drawing_session)
    expect(response.parsed_body.at_css('[data-date="2026-11-16"]').text).to include('6:30 PM')
    expect(response.parsed_body.at_css('[data-date="2026-11-17"]').text).to include('2:00 PM', 'Extra drawing.')
    expect(response.parsed_body.at_css('[data-date="2026-11-23"]').text).to include('Blocked', 'Holiday closure.')
    expect(response.body).to include('Manage Schedule', 'Edit Day')
  end

  it 'shows form errors without persisting malformed dates or missing reasons' do
    sign_in(create_user(roles: ['system_admin']))
    save_day(reason: ' ')
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Explanation', 'blank')
    save_day(date: '')
    expect(response).to have_http_status(:unprocessable_content)
    save_day(date: 'not-a-date')
    expect(response).to have_http_status(:unprocessable_content)
    expect(drawing_session.schedule_exceptions).to be_empty
  end

  it 'edits the default start time through session settings and displays the saved time' do
    sign_in(create_user(roles: ['system_admin']))
    patch drawing_session_path(drawing_session), params: { drawing_session: { start_time: '19:15' } }
    expect(response).to redirect_to(drawing_session_path(drawing_session))
    follow_redirect!
    expect(response.body).to include('7:15 PM')
    patch drawing_session_path(drawing_session), params: { drawing_session: { start_time: 'invalid' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(drawing_session.reload.start_time).to eq('19:15')
  end
end
