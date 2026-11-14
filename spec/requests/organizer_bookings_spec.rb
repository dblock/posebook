# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Organizer bookings', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program }
  let(:participant) { create_user }
  let(:organizer) { create_user }

  before do
    grant_participant_access(program, participant)
    grant_coordinator_access(program, organizer)
    sign_in(organizer)
  end

  def booking_params(**overrides)
    { booking: { user_id: participant.id.to_s, date: '2026-11-16', attendance: 'unconfirmed',
                 reason: 'Agreed with the participant.',
                 lock_version: program.bookings.upcoming.first&.lock_version || 0 }
                 .merge(overrides) }
  end

  def reserve
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-16'))
  end

  it 'creates a booking for an assigned participant without granting unrelated administrator permissions' do
    get new_program_organizer_booking_path(program)
    expect(response.body).to include('Schedule a Model', participant.name)
    expect(response.parsed_body.at_css('#booking_attendance option[value="confirmed"]').text).to eq('Confirmed')
    post program_organizer_bookings_path(program), params: booking_params
    record = track_booking(program.bookings.first)
    expect(record).to have_attributes(user_id: participant.id, created_by_id: organizer.id)
    get edit_venue_path(program.venue)
    expect(response).to have_http_status(:not_found)
    get admin_users_path
    expect(response).to have_http_status(:forbidden)
  end

  it 'edits and clears attendance after the participant cutoff while retaining attributed changes' do
    record = reserve
    get edit_program_organizer_booking_path(program, record)
    expect(response.body).to include('Edit Booking', 'Unconfirmed')
    patch program_organizer_booking_path(program, record),
          params: booking_params(attendance: 'confirmed')
    expect(record.reload.attendance_confirmed_by_id).to eq(organizer.id)
    follow_redirect!
    expect(response.body).to include('Confirmed on ')
    patch program_organizer_booking_path(program, record), params: booking_params
    expect(record.reload.attendance_confirmed?).to be(false)
    expect(record.attendance_changes.pluck('confirmed')).to eq([true, false])
    expect(record.attendance_changes.last).to include('changed_by_id' => organizer.id,
                                                      'reason' => 'Agreed with the participant.')
  end

  it 'explains a date claimed after the organizer opened the form without creating a second booking' do
    get new_program_organizer_booking_path(program)
    other = create_user
    grant_participant_access(program, other)
    track_booking(BookingMutation.new(program: program, user: other).book(date: '2026-11-16'))
    post program_organizer_bookings_path(program), params: booking_params
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('someone else just booked that date', 'Please choose another available date.')
    expect(response.parsed_body.at_css('#booking_date')['value']).to eq('2026-11-16')
    expect(program.bookings.count).to eq(1)
  end

  it 'reassigns the participant and date after the cutoff with linked history and a single updated claim' do
    record = reserve
    other = create_user
    grant_participant_access(program, other)
    patch program_organizer_booking_path(program, record),
          params: booking_params(user_id: other.id.to_s, date: '2026-11-23')
    replacement = track_booking(program.bookings.find_by(previous_booking_id: record.id))
    expect(record.reload).to have_attributes(status: 'rescheduled', user_id: participant.id,
                                             changed_by_id: organizer.id)
    expect(replacement).to have_attributes(user_id: other.id, attendance_confirmed_at: nil)
    expect(BookingClaim.where(program_id: program.id).count).to eq(1)
    expect(BookingClaim.find_by(booking_id: replacement.id).user_id).to eq(other.id)
  end

  it 'cancels a booking after the cutoff without removing its ledger or confirmation history' do
    record = reserve
    patch program_organizer_booking_path(program, record),
          params: booking_params(attendance: 'confirmed')
    post cancel_program_organizer_booking_path(program, record),
         params: booking_params(reason: 'Model is ill.')
    expect(record.reload).to have_attributes(status: 'canceled', reason: 'Model is ill.', changed_by_id: organizer.id)
    expect(record.attendance_confirmed?).to be(false)
    expect(record.attendance_confirmed_at).to be_present
    expect(record.attendance_changes.pluck('confirmed')).to eq([true])
    expect(BookingClaim.where(booking_id: record.id)).to be_empty
    get program_path(program)
    history = response.parsed_body.at_xpath('//section[h2="Session Booking History"]')
    status = history.at_css('tbody tr td:nth-child(3)')
    expect(status.text.strip).to eq('Canceled')
    expect(status.at_css('.attendance-confirmed')).to be_nil
  end

  it 'submits the organizer cancellation form successfully with forgery protection enabled' do
    protection = OrganizerBookingsController.allow_forgery_protection
    record = reserve
    OrganizerBookingsController.allow_forgery_protection = true
    get edit_program_organizer_booking_path(program, record)
    form = response.parsed_body.at_css('form[action$="/cancel"]')
    post form['action'], params: { authenticity_token: form.at_css('input[name="authenticity_token"]')['value'],
                                   booking: { reason: 'Agreed cancellation.', lock_version: record.lock_version } }
    expect(response).to redirect_to(program_path(program, month: '2026-11'))
    expect(record.reload.status).to eq('canceled')
  ensure
    OrganizerBookingsController.allow_forgery_protection = protection
  end

  it 'rejects missing explanations and invalid attendance while preserving submitted form values' do
    record = reserve
    patch program_organizer_booking_path(program, record), params: booking_params(reason: '')
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Please tell us what changed')
    patch program_organizer_booking_path(program, record),
          params: booking_params(attendance: 'anything')
    expect(response).to have_http_status(:unprocessable_content)
    expect(record.reload.attendance_changes).to be_empty
    expect(record.status).to eq('confirmed')
  end

  it 'rejects an old organizer form instead of clearing a newer confirmation' do
    record = reserve
    get edit_program_organizer_booking_path(program, record)
    version = response.parsed_body.at_css('input[name="booking[lock_version]"]')['value']
    other = create_user
    grant_coordinator_access(program, other)
    OrganizerBookingMutation.new(program: program, user: other)
                            .update(record.id, booking_params(attendance: 'confirmed')[:booking])
    patch program_organizer_booking_path(program, record), params: booking_params(lock_version: version)
    expect(response).to redirect_to(program_path(program))
    follow_redirect!
    expect(response.body).to include('changed while you were editing', 'Confirmed')
    expect(record.reload.attendance_confirmed_by_id).to eq(other.id)
    expect(record.attendance_changes.size).to eq(1)
    expect(record.lock_version).to eq(1)
  end

  it 'rejects foreign participants and session bookings, including direct submissions from a participant' do
    record = reserve
    other = create_user
    post program_organizer_bookings_path(program),
         params: booking_params(user_id: other.id.to_s, date: '2026-11-23')
    expect(response).to have_http_status(:unprocessable_content)
    get edit_program_organizer_booking_path(create_program, record)
    expect(response).to have_http_status(:not_found)
    sign_in(participant)
    patch program_organizer_booking_path(program, record),
          params: booking_params(attendance: 'confirmed')
    expect(response).to have_http_status(:not_found)
    expect(record.reload.attendance_confirmed?).to be(false)
  end
end
