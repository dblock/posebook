# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Drawing schedules', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:venue) { create_venue }

  def save_day(**attributes)
    patch venue_schedule_path(venue), params: {
      schedule: { date: '2026-11-16', mode: 'open', start_time: '19:30', reason: 'Later start.' }.merge(attributes)
    }
    venue.schedule_exceptions.each { |exception| track_record(exception) }
  end

  it 'lets an assigned organizer manage times but not edit regular venue settings' do
    organizer = create_user
    grant_schedule_access(venue, organizer)
    sign_in(organizer)
    get venue_schedule_path(venue, date: '2026-11-16')
    expect(response.body).to include('Drawing Schedule', 'Save Schedule')
    save_day
    expect(response).to redirect_to(venue_path(venue, month: '2026-11'))
    expect(venue.schedule_exceptions.first.history_tracks.last.modifier_id).to eq(organizer.id)
    patch venue_path(venue), params: { venue: { start_time: '20:30' } }
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not expose schedule controls or allow writes by models or organizers from another venue' do
    user = create_user
    grant_model_access(venue, user)
    grant_schedule_access(create_venue, user)
    sign_in(user)
    get venue_path(venue)
    expect(response.body).not_to include('Manage Schedule', 'Edit Day')
    get venue_schedule_path(venue)
    expect(response).to have_http_status(:not_found)
    save_day
    expect(response).to have_http_status(:not_found)
    expect(venue.schedule_exceptions).to be_empty
  end

  it 'renders calendar times, one-off openings, holiday reasons, and manager edit links' do
    sign_in(create_user(roles: ['system_admin']))
    save_day(date: '2026-11-17', start_time: '14:00', reason: 'Extra drawing.')
    save_day(date: '2026-11-23', mode: 'closed', reason: 'Holiday closure.')
    get venue_path(venue)
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
    expect(venue.schedule_exceptions).to be_empty
  end

  it 'edits the default start time through venue settings and displays the saved time' do
    sign_in(create_user(roles: ['system_admin']))
    patch venue_path(venue), params: { venue: { start_time: '19:15' } }
    expect(response).to redirect_to(venue_path(venue))
    follow_redirect!
    expect(response.body).to include('7:15 PM')
    patch venue_path(venue), params: { venue: { start_time: 'invalid' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(venue.reload.start_time).to eq('19:15')
  end
end
