# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Gender-aware booking', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:venue) { create_venue(no_consecutive_genders: ['male']) }
  let(:model) { create_user(gender: 'male') }
  let(:organizer) { create_user }

  before do
    grant_model_access(venue, model)
    grant_schedule_access(venue, organizer)
  end

  def reserve(date, gender: 'male')
    user = create_user(gender: gender, public_profile_private: true)
    grant_model_access(venue, user)
    track_booking(BookingMutation.new(venue: venue, user: user).book(date: date))
  end

  def organizer_booking(**overrides)
    { date: '2026-11-23', user_id: model.id.to_s, attendance: 'unconfirmed' }.merge(overrides)
  end

  def calendar_day(date)
    response.parsed_body.at_css("[data-date=\"#{date}\"]")
  end

  def update_profile(**overrides)
    patch profile_path, params: { user: { name: model.name, email: model.email }.merge(overrides) }
  end

  it 'blocks both adjacent choices in the model calendar without publishing another model gender' do
    reserve('2026-11-23')
    sign_in(model)
    get venue_path(venue)
    %w[2026-11-16 2026-11-30].each do |date|
      expect(calendar_day(date)['class']).to eq('blocked')
      expect(calendar_day(date).text).to include('Gender rule')
      expect(calendar_day(date).css('form, button')).to be_empty
    end
    expect(calendar_day('2026-11-23').text).to include('To be announced')
    expect(calendar_day('2026-11-23').text).not_to include('Male')
  end

  it 'enforces the rule on direct submissions even with a forged organizer override' do
    reserve('2026-11-16')
    sign_in(model)
    post venue_model_bookings_path(venue),
         params: { date: '2026-11-23', override_gender_rule: '1', reason: 'Override.' }
    expect(response).to redirect_to(venue_path(venue))
    expect(flash[:alert]).to include('consecutive-gender rule')
    expect(ModelBooking.where(user_id: model.id)).to be_empty
  end

  it 'asks existing models to select a gender and enables their calendar after a no-JavaScript profile save' do
    model.update!(gender: nil)
    sign_in(model)
    get venue_path(venue)
    expect(response.body).to include(edit_profile_path, 'before your next booking')
    expect(calendar_day('2026-11-16').css('form')).to be_empty
    update_profile(gender: 'female')
    expect(response).to redirect_to(profile_path)
    get venue_path(venue)
    expect(calendar_day('2026-11-16')['class']).to eq('available')
    expect(calendar_day('2026-11-16').css('form')).to be_present
    expect(model.reload.gender).to eq('female')
  end

  it 'rejects invalid gender values and audits valid changes without accepting roles' do
    sign_in(model)
    update_profile(gender: 'invalid')
    expect(response).to have_http_status(:unprocessable_content)
    expect(model.reload.gender).to eq('male')
    update_profile(gender: 'other', roles: ['system_admin'])
    expect(model.reload).to have_attributes(gender: 'other', roles: [])
    change = model.history_tracks.where(action: 'update').last
    expect(change.modified).to include('gender' => 'other')
    expect(change.modifier_id).to eq(model.id)
  end

  it 'accepts the gender selection during invited registration' do
    invitation = create_model_invitation(venue, organizer)
    attributes = user_attributes(gender: 'female')
    post invited_registration_path, params: { token: invitation.token, user: attributes }
    registered = track_record(User.find_by(email: attributes[:email]))
    track_model_membership(venue, registered)
    expect(response).to redirect_to(venue_path(venue))
    expect(registered.gender).to eq('female')
  end

  it 'lets system admins edit the private gender without granting that permission to organizers' do
    sign_in(organizer)
    patch admin_user_path(model), params: { user: { gender: 'other' } }
    expect(response).to have_http_status(:forbidden)
    admin = create_user(roles: ['system_admin'])
    sign_in(admin)
    patch admin_user_path(model), params: { user: { gender: 'other' } }
    expect(response).to redirect_to(admin_users_path)
    expect(model.reload.gender).to eq('other')
    expect(model.history_tracks.last.modifier_id).to eq(admin.id)
  end

  it 'limits venue restrictions to admins and saves separate toggles including clearing all of them' do
    sign_in(organizer)
    patch venue_path(venue), params: { venue: { no_consecutive_genders: ['female'] } }
    expect(response).to have_http_status(:forbidden)
    sign_in(create_user(roles: ['system_admin']))
    [%w[male other], [], %w[female]].each do |genders|
      patch venue_path(venue), params: { venue: { no_consecutive_genders: [''] + genders } }
      expect(response).to redirect_to(venue_path(venue))
      expect(venue.reload.no_consecutive_genders).to eq(genders)
    end
    patch venue_path(venue), params: { venue: { no_consecutive_genders: ['invalid'] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(venue.reload.no_consecutive_genders).to eq(['female'])
  end

  it 'requires an explicit organizer override and retains its explanation and actor privately' do
    reserve('2026-11-16')
    sign_in(organizer)
    post venue_organizer_bookings_path(venue), params: { booking: organizer_booking(reason: 'Agreed by phone.') }
    expect(response).to have_http_status(:unprocessable_content)
    post venue_organizer_bookings_path(venue), params: { booking: organizer_booking(override_gender_rule: '1') }
    expect(response).to have_http_status(:unprocessable_content)
    post venue_organizer_bookings_path(venue), params: { booking: organizer_booking(override_gender_rule: '1',
                                                                                    reason: 'Agreed by phone.') }
    booking = track_booking(ModelBooking.find_by(venue_id: venue.id, user_id: model.id))
    expect(booking).to have_attributes(gender_override_reason: 'Agreed by phone.', created_by_id: organizer.id)
    follow_redirect!
    expect(response.body).to include('Gender-rule override: Agreed by phone.')
    delete session_path
    get venue_path(venue)
    expect(response.body).not_to include('Gender-rule', 'Agreed by phone.', 'Gender rules', '(Male)')
  end

  it 'does not let organizers override a missing gender selection' do
    model.update!(gender: nil)
    sign_in(organizer)
    post venue_organizer_bookings_path(venue), params: { booking: organizer_booking(override_gender_rule: '1',
                                                                                    reason: 'Agreed by phone.') }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Select a gender')
    expect(ModelBooking.where(user_id: model.id)).to be_empty
  end

  it 'checks organizer replacements without losing the original and records an explicit override' do
    reserve('2026-11-16')
    original = track_booking(BookingMutation.new(venue: venue, user: model).book(date: '2026-11-30'))
    sign_in(organizer)
    patch venue_organizer_booking_path(venue, original),
          params: { booking: organizer_booking(reason: 'Agreed by phone.') }
    expect(response).to have_http_status(:unprocessable_content)
    expect(original.reload.status).to eq('confirmed')
    patch venue_organizer_booking_path(venue, original),
          params: { booking: organizer_booking(override_gender_rule: '1', reason: 'Agreed by phone.') }
    replacement = track_booking(venue.model_bookings.find_by(previous_booking_id: original.id))
    expect(replacement).to have_attributes(date: Date.new(2026, 11, 23), gender_override_reason: 'Agreed by phone.')
    expect(original.reload.status).to eq('rescheduled')
    expect(ModelBookingClaim.find_by(model_booking_id: replacement.id).date).to eq(replacement.date)
  end

  it 'excludes the original reservation in the rescheduling calendar' do
    original = track_booking(BookingMutation.new(venue: venue, user: model).book(date: '2026-11-23'))
    sign_in(model)
    get edit_venue_model_booking_path(venue, original)
    expect(calendar_day('2026-11-30')['class']).to eq('available')
    expect(calendar_day('2026-11-30').at_css('button')['value']).to eq('2026-11-30')
  end
end
