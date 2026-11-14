# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Gender-aware booking', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program(no_consecutive_genders: ['male']) }
  let(:participant) { create_user(gender: 'male') }
  let(:organizer) { create_user }

  before do
    grant_participant_access(program, participant)
    grant_coordinator_access(program, organizer)
  end

  def reserve(date, gender: 'male')
    user = create_user(gender: gender, public_profile_private: true)
    grant_participant_access(program, user)
    track_booking(BookingMutation.new(program: program, user: user).book(date: date))
  end

  def organizer_booking(**overrides)
    { date: '2026-11-23', user_id: participant.id.to_s, attendance: 'unconfirmed', lock_version: 0 }.merge(overrides)
  end

  def calendar_day(date)
    response.parsed_body.at_css("[data-date=\"#{date}\"]")
  end

  def update_profile(**overrides)
    patch profile_path, params: { user: { name: participant.name, email: participant.email }.merge(overrides) }
  end

  it 'blocks both adjacent choices in the participant calendar without publishing another participant gender' do
    reserve('2026-11-23')
    sign_in(participant)
    get program_path(program)
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
    sign_in(participant)
    post program_bookings_path(program),
         params: { date: '2026-11-23', override_gender_rule: '1', reason: 'Override.' }
    expect(response).to redirect_to(program_path(program, month: '2026-11'))
    expect(flash[:alert]).to include('consecutive-gender rule')
    expect(Booking.where(user_id: participant.id)).to be_empty
  end

  it 'asks existing participants to select a gender and enables their calendar after a no-JavaScript profile save' do
    participant.update!(gender: nil)
    sign_in(participant)
    get program_path(program)
    expect(response.body).to include(edit_profile_path, 'before your next booking')
    expect(calendar_day('2026-11-16').css('form')).to be_empty
    update_profile(gender: 'female')
    expect(response).to redirect_to(profile_path)
    get program_path(program)
    expect(calendar_day('2026-11-16')['class']).to eq('available')
    expect(calendar_day('2026-11-16').css('form')).to be_present
    expect(participant.reload.gender).to eq('female')
  end

  it 'rejects invalid gender values and audits valid changes without accepting roles' do
    sign_in(participant)
    update_profile(gender: 'invalid')
    expect(response).to have_http_status(:unprocessable_content)
    expect(participant.reload.gender).to eq('male')
    update_profile(gender: 'other', roles: ['system_admin'])
    expect(participant.reload).to have_attributes(gender: 'other', roles: [])
    change = participant.history_tracks.where(action: 'update').last
    expect(change.modified).to include('gender' => 'other')
    expect(change.modifier_id).to eq(participant.id)
  end

  it 'accepts the gender selection during invited registration' do
    invitation = create_participant_invitation(program, organizer)
    attributes = user_attributes(gender: 'female')
    post invited_registration_path, params: { token: invitation.token, user: attributes }
    registered = track_record(User.find_by(email: attributes[:email]))
    track_participant_membership(program, registered)
    expect(response).to redirect_to(program_path(program))
    expect(registered.gender).to eq('female')
  end

  it 'lets system admins edit the private gender without granting that permission to organizers' do
    sign_in(organizer)
    patch admin_user_path(participant), params: { user: { gender: 'other' } }
    expect(response).to have_http_status(:forbidden)
    admin = create_user(roles: ['system_admin'])
    sign_in(admin)
    patch admin_user_path(participant), params: { user: { gender: 'other' } }
    expect(response).to redirect_to(admin_users_path)
    expect(participant.reload.gender).to eq('other')
    expect(participant.history_tracks.last.modifier_id).to eq(admin.id)
  end

  it 'lets coordinators and admins save separate session restrictions including clearing all of them' do
    sign_in(organizer)
    patch program_path(program), params: { program: { no_consecutive_genders: ['female'] } }
    expect(response).to redirect_to(program_path(program))
    sign_in(create_user(roles: ['system_admin']))
    [%w[male other], [], %w[female]].each do |genders|
      patch program_path(program),
            params: { program: { no_consecutive_genders: [''] + genders } }
      expect(response).to redirect_to(program_path(program))
      expect(program.reload.no_consecutive_genders).to eq(genders)
    end
    patch program_path(program), params: { program: { no_consecutive_genders: ['invalid'] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(program.reload.no_consecutive_genders).to eq(['female'])
  end

  it 'requires an explicit organizer override and retains its explanation and actor privately' do
    reserve('2026-11-16')
    sign_in(organizer)
    post program_organizer_bookings_path(program),
         params: { booking: organizer_booking(reason: 'Agreed by phone.') }
    expect(response).to have_http_status(:unprocessable_content)
    post program_organizer_bookings_path(program),
         params: { booking: organizer_booking(override_gender_rule: '1') }
    expect(response).to have_http_status(:unprocessable_content)
    attributes = organizer_booking(override_gender_rule: '1', reason: 'Agreed by phone.')
    post program_organizer_bookings_path(program), params: { booking: attributes }
    booking = track_booking(Booking.find_by(program_id: program.id, user_id: participant.id))
    expect(booking).to have_attributes(gender_override_reason: 'Agreed by phone.', created_by_id: organizer.id)
    follow_redirect!
    expect(response.body).to include('Gender-rule override: Agreed by phone.')
    delete session_path
    get program_path(program)
    expect(response.body).not_to include('Gender-rule', 'Agreed by phone.', 'Gender rules', '(Male)')
  end

  it 'does not let organizers override a missing gender selection' do
    participant.update!(gender: nil)
    sign_in(organizer)
    post program_organizer_bookings_path(
      program
    ), params: { booking: organizer_booking(
      override_gender_rule: '1',
      reason: 'Agreed by phone.'
    ) }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Select a gender')
    expect(Booking.where(user_id: participant.id)).to be_empty
  end

  it 'checks organizer replacements without losing the original and records an explicit override' do
    reserve('2026-11-16')
    original = track_booking(BookingMutation.new(program: program,
                                                 user: participant).book(date: '2026-11-30'))
    sign_in(organizer)
    patch program_organizer_booking_path(program, original),
          params: { booking: organizer_booking(reason: 'Agreed by phone.') }
    expect(response).to have_http_status(:unprocessable_content)
    expect(original.reload.status).to eq('confirmed')
    patch program_organizer_booking_path(program, original),
          params: { booking: organizer_booking(override_gender_rule: '1', reason: 'Agreed by phone.') }
    replacement = track_booking(program.bookings.find_by(previous_booking_id: original.id))
    expect(replacement).to have_attributes(date: Date.new(2026, 11, 23), gender_override_reason: 'Agreed by phone.')
    expect(original.reload.status).to eq('rescheduled')
    expect(BookingClaim.find_by(booking_id: replacement.id).date).to eq(replacement.date)
  end

  it 'excludes the original reservation in the rescheduling calendar' do
    original = track_booking(BookingMutation.new(program: program,
                                                 user: participant).book(date: '2026-11-23'))
    sign_in(participant)
    get edit_program_booking_path(program, original)
    expect(calendar_day('2026-11-30')['class']).to eq('available')
    expect(calendar_day('2026-11-30').at_css('button')['value']).to eq('2026-11-30')
  end
end
