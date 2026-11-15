# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Program routes', :aggregate_failures, type: :routing do
  it 'uses programs for the directory, details, and venue-scoped creation' do
    expect(get: '/programs').to route_to('programs#index')
    expect(get: '/programs/weekly-studio').to route_to('programs#show', id: 'weekly-studio')
    expect(get: '/venues/art-studio/programs/new').to route_to('programs#new', venue_id: 'art-studio')
    expect(post: '/venues/art-studio/programs').to route_to('programs#create', venue_id: 'art-studio')
  end

  it 'keeps bookings, galleries, and Google Calendar nested under programs' do
    expect(post: '/programs/weekly-studio/bookings').to route_to('bookings#create', program_id: 'weekly-studio')
    expect(post: '/programs/weekly-studio/photos').to route_to('program_photos#create', program_id: 'weekly-studio')
    expect(get: '/programs/weekly-studio/google_calendar')
      .to route_to('google_calendars#show', program_id: 'weekly-studio')
  end

  it 'removes session-based program routes without changing authentication' do
    %w[/sessions /sessions/weekly-studio /sessions/weekly-studio/photos
       /sessions/weekly-studio/google_calendar /venues/art-studio/sessions/new].each do |path|
      expect(get: path).not_to be_routable
    end
    expect(post: '/venues/art-studio/sessions').not_to be_routable
    expect(get: '/session/new').to route_to('sessions#new')
    expect(post: '/session').to route_to('sessions#create')
    expect(delete: '/session').to route_to('sessions#destroy')
  end
end
