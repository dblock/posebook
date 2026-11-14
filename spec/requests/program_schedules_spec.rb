# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Booking schedules', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program }

  def save_day(**attributes)
    patch program_schedule_path(program), params: {
      schedule: { date: '2026-11-16', mode: 'open', start_time: '19:30', reason: 'Later start.' }.merge(attributes)
    }
    program.schedule_exceptions.each { |exception| track_record(exception) }
  end

  it 'lets an assigned coordinator manage exceptions and regular session settings' do
    organizer = create_user
    grant_coordinator_access(program, organizer)
    sign_in(organizer)
    get program_schedule_path(program, date: '2026-11-16')
    expect(response.body).to include('Program Schedule', 'Save Schedule')
    save_day
    expect(response).to redirect_to(program_path(program, month: '2026-11'))
    expect(program.schedule_exceptions.first.history_tracks.last.modifier_id).to eq(organizer.id)
    patch program_path(program), params: { program: { start_time: '20:30' } }
    expect(response).to redirect_to(program_path(program))
    expect(program.reload.start_time).to eq('20:30')
  end

  it 'does not expose schedule controls or allow writes by participants or organizers from another program' do
    user = create_user
    grant_participant_access(program, user)
    grant_coordinator_access(create_program, user)
    sign_in(user)
    get program_path(program)
    expect(response.body).not_to include('Manage Schedule', 'Edit Day')
    get program_schedule_path(program)
    expect(response).to have_http_status(:not_found)
    save_day
    expect(response).to have_http_status(:not_found)
    expect(program.schedule_exceptions).to be_empty
  end

  it 'renders calendar times, one-off openings, holiday reasons, and manager edit links' do
    sign_in(create_user(roles: ['system_admin']))
    save_day(date: '2026-11-17', start_time: '14:00', reason: 'Extra booking.')
    save_day(date: '2026-11-23', mode: 'closed', reason: 'Holiday closure.')
    get program_path(program)
    expect(response.parsed_body.at_css('[data-date="2026-11-16"]').text).to include('9:00 AM')
    expect(response.parsed_body.at_css('[data-date="2026-11-17"]').text).to include('2:00 PM', 'Extra booking.')
    expect(response.parsed_body.at_css('[data-date="2026-11-23"]').text).to include('Blocked', 'Holiday closure.')
    expect(response.body).to include('Manage Schedule', 'Edit Day')
  end

  it 'shows restored schedules with one word in the badge and explanations outside it' do
    sign_in(create_user(roles: ['system_admin']))
    save_day(mode: 'regular')
    get program_schedule_path(program)
    expect(response.parsed_body.css('.status-label').map(&:text)).to eq(['Regular'])
    expect(response.parsed_body.text).to include('schedule restored', 'Later start.')
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
    expect(program.schedule_exceptions).to be_empty
  end

  it 'edits the default start time through session settings and displays the saved time' do
    sign_in(create_user(roles: ['system_admin']))
    patch program_path(program), params: { program: { start_time: '19:15' } }
    expect(response).to redirect_to(program_path(program))
    follow_redirect!
    expect(response.body).to include('7:15 PM')
    patch program_path(program), params: { program: { start_time: 'invalid' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(program.reload.start_time).to eq('19:15')
  end
end
