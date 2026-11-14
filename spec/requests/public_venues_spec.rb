# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public venue calendars', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:venue) { create_venue(instructions: 'Private door instructions.', model_pay: 321) }
  let(:private_booking) do
    scheduled_booking('2026-11-16', name: 'Private Account Name', display_name: 'Public Artist',
                                    phone: '+12125551234', instagram_url: '@private_model')
  end
  let(:tagged_booking) do
    scheduled_booking('2026-11-23', name: 'Fallback Artist', instagram_url: '@public_model',
                                    instagram_tagging_allowed: true)
  end

  def scheduled_booking(date, at: venue, **attributes)
    user = create_user(**attributes)
    grant_model_access(at, user)
    track_booking(BookingMutation.new(venue: at, user: user).book(date: date))
  end

  def expect_public_only
    expect(response.body).not_to include(venue.instructions, 'Model Pay', 'Booking History',
                                         'Manage Schedule', 'Invite a Model', 'Your Upcoming Booking')
    expect(response.parsed_body.css('.calendar form, .calendar button')).to be_empty
  end

  it 'allows guests through slugs, shortcuts, and IDs while exposing only public model identity' do
    hidden = private_booking.user
    tagged_booking
    [venue_path(venue), venue_shortcut_path(venue), venue_path(venue.id)].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(venue.name, venue.address, 'Monday at 6:30 PM', 'Public Artist',
                                       'Fallback Artist')
      expect(response.body).not_to include(hidden.name, hidden.email, hidden.phone, hidden.id.to_s, 'private_model')
      link = response.parsed_body.at_css('a[href="https://www.instagram.com/public_model/"]')
      expect(link.text).to eq('@public_model')
      expect_public_only
    end
  end

  it 'does not turn a signed-in visitor into a member or expose private endpoints through forged parameters' do
    private_booking
    visitor = create_user
    sign_in(visitor)
    get venue_path(venue), params: { manage_schedule: '1', can_book: '1', public_view: 'false' }
    expect(response).to have_http_status(:ok)
    expect_public_only
    [venue_models_path(venue), venue_schedule_path(venue), new_venue_model_invitation_path(venue)].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
    post venue_model_bookings_path(venue), params: { date: '2026-11-30' }
    expect(response).to have_http_status(:not_found)
    expect(VenueMembership.where(user_id: visitor.id)).to be_empty
  end

  it 'hides canceled records, other venues, and internal schedule explanations' do
    canceled = scheduled_booking('2026-11-16', display_name: 'Canceled Model')
    BookingMutation.new(venue: venue, user: canceled.user).cancel(booking: canceled, reason: 'Private cancellation.')
    scheduled_booking('2026-11-23', at: create_venue, display_name: 'Other Venue Model')
    track_record(VenueScheduleException.create!(venue: venue, date: Date.new(2026, 11, 30),
                                                mode: 'closed', reason: 'Private closure explanation.'))
    track_record(VenueScheduleException.create!(venue: venue, date: Date.new(2026, 11, 17),
                                                mode: 'open', start_time: '20:00', reason: 'Private extra drawing.'))
    get venue_path(venue)
    expect(response.body).not_to include('Canceled Model', 'Other Venue Model', 'Private cancellation.',
                                         'Private closure explanation.', 'Private extra drawing.')
    expect(response.parsed_body.at_css('[data-date="2026-11-30"]').text).to include('Closed')
    expect(response.parsed_body.at_css('[data-date="2026-11-17"]').text).to include('8:00 PM')
    expect_public_only
  end

  it 'keeps inactive accounts reserved without publishing their identity or Instagram' do
    tagged_booking.user.update!(active: false)
    get venue_path(venue)
    expect(response.parsed_body.at_css('[data-date="2026-11-23"]').text).to include('Booked')
    expect(response.body).not_to include('Fallback Artist', 'public_model')
  end

  it 'announces private models anonymously to guests and other models' do
    booking = scheduled_booking('2026-11-16', name: 'Private Account', display_name: 'Hidden Alias',
                                              instagram_url: '@private_model', instagram_tagging_allowed: true,
                                              public_profile_private: true)
    [nil, create_user].each do |viewer|
      grant_model_access(venue, viewer) if viewer
      sign_in(viewer) if viewer
      get venue_path(venue)
      expect(response.parsed_body.at_css('[data-date="2026-11-16"]').text).to include('To be announced')
      expect(response.body).not_to include(booking.user.name, 'Hidden Alias', 'private_model',
                                           booking.user.email, booking.user.id.to_s)
    end
  end

  it 'lets authorized managers identify private models in the calendar and retained history' do
    model = private_booking.user
    model.update!(public_profile_private: true, instagram_tagging_allowed: true)
    sign_in(create_user(roles: ['system_admin']))
    get venue_path(venue)
    expect(response.parsed_body.at_css('[data-date="2026-11-16"]').text).to include(model.name)
    history = response.parsed_body.at_xpath('//section[h2="Venue Booking History"]')
    expect(history.text).to include(model.name)
    expect(response.body).not_to include('private_model')
  end

  it 'uses current public preferences and removes Instagram immediately after consent is revoked' do
    user = tagged_booking.user
    get venue_path(venue)
    expect(response.body).to include('https://www.instagram.com/public_model/')
    user.update!(display_name: 'New Public Name', instagram_tagging_allowed: false)
    get venue_path(venue, month: '2026-11')
    expect(response.body).to include('New Public Name')
    expect(response.body).not_to include('Fallback Artist', 'public_model', user.email)
  end

  it 'retains personal booking information for members and management only for managers' do
    sign_in(private_booking.user)
    get venue_path(venue)
    expect(response.body).to include(venue.instructions, 'Model Pay', 'Your Booking History', 'Your Upcoming Booking')
    expect(response.body).not_to include('Venue Booking History', 'Manage Schedule')
    member_context = response.parsed_body.at_css('[data-calendar]')['data-calendar-context']
    sign_in(create_user(roles: ['system_admin']))
    get venue_path(venue)
    expect(response.body).to include(venue.instructions, 'Model Pay', 'Venue Booking History', 'Manage Schedule')
    expect(response.parsed_body.at_css('[data-calendar]')['data-calendar-context']).not_to eq(member_context)
  end
end
