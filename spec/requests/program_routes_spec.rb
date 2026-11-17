# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Program page routes', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program }

  it 'uses dedicated calendar and history paths in program navigation' do
    sign_in(create_user(roles: ['system_admin']))
    get calendar_program_path(program)
    links = response.parsed_body.css('.program-tabs a, .program-secondary-tabs a').pluck('href')
    expect(links).to include(calendar_program_path(program), history_program_path(program))
    expect(links).not_to include(a_string_including('section='))
    expect(response.parsed_body.at_css('.program-secondary-tabs [aria-current="page"]').text).to eq('Calendar')
  end

  it 'keeps dedicated page selection independent of a forged section query' do
    get calendar_program_path(program), params: { section: 'history' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css('[data-calendar]')).to be_present
  end

  it 'keeps the selected month as query state on the dedicated calendar page' do
    get calendar_program_path(program), params: { month: '2026-12' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css('[data-calendar-month] time')['datetime']).to eq('2026-12')
    expect(response.parsed_body.at_css('.next-session')).to be_nil
  end

  it 'keeps history private and uses its route even when a query selects a public section' do
    get history_program_path(program), params: { section: 'calendar' }
    expect(response).to have_http_status(:not_found)
    member = create_user
    grant_participant_access(program, member)
    sign_in(member)
    get history_program_path(program), params: { section: 'calendar' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Your Booking History')
  end

  it 'does not let query selectors or calendar headers change the overview page' do
    get program_path(program), params: { section: 'history', month: '2027-02' },
                               headers: { 'X-Posebook-Calendar-Context' => 'public' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css('.next-session')).to be_present
    expect(response.parsed_body.at_css('[data-calendar-month] time')['datetime']).to eq('2026-11')
  end
end
