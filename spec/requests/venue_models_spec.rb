# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Venue model access', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:venue) { create_venue }
  let(:organizer) { create_user }
  let(:model) { create_user(name: 'Invited Model') }
  let(:membership) { grant_model_access(venue, model) }

  def manage_models
    grant_schedule_access(venue, organizer)
    sign_in(organizer)
  end

  it 'sends an individual email and records who opened booking access' do
    venue.update!(start_time: '19:15')
    membership
    manage_models
    post invite_venue_model_path(venue, membership)
    expect(response).to redirect_to(venue_models_path(venue))
    expect(ActionMailer::Base.deliveries.last.to).to eq([model.email])
    expect(ActionMailer::Base.deliveries.last.text_part.body.decoded).to include('booking_invitation=1', venue.slug)
    [ActionMailer::Base.deliveries.last.text_part, ActionMailer::Base.deliveries.last.html_part].each do |part|
      expect(part.body.decoded).to include('Monday at 7:15 PM (America/New_York)')
    end
    expect(membership.reload.history_tracks.last.modifier_id).to eq(organizer.id)
  end

  it 'bulk invites only active models at this venue without upcoming bookings or pauses' do
    available = membership
    paused = grant_model_access(venue, create_user)
    paused.update!(model_paused: true, model_pause_reason: 'Private explanation.')
    booked_user = create_user
    grant_model_access(venue, booked_user)
    track_booking(BookingMutation.new(venue: venue, user: booked_user).book(date: '2026-11-16'))
    grant_model_access(venue, create_user(active: false))
    grant_model_access(create_venue, create_user)
    manage_models
    post invite_all_venue_models_path(venue)
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[available.user.email]])
    follow_redirect!
    expect(response.body).to include('3 booked, paused, or inactive models skipped')
  end

  it 'keeps granted permission and reports failed email rather than claiming delivery succeeded' do
    membership
    manage_models
    allow(BookingInvitationMailer).to receive(:invite).and_raise(IOError, 'SMTP failed')
    post invite_venue_model_path(venue, membership)
    follow_redirect!
    expect(response.body).to include('Booking enabled, but invitation email could not be sent')
    expect(ModelBookingAccess.new(membership.reload).allowed?).to be(true)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'reports unavailable email configuration while preserving the explicit booking grant' do
    membership
    manage_models
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(false)
    post invite_venue_model_path(venue, membership)
    follow_redirect!
    expect(response.body).to include('Booking enabled, but invitation email could not be sent')
    expect(membership.reload.booking_invited_by_id).to eq(organizer.id)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'requires manager scope and does not allow cross-venue membership mutations' do
    membership
    manage_models
    other = grant_model_access(create_venue, create_user)
    post pause_venue_model_path(venue, other), params: { reason: 'Forbidden.' }
    expect(response).to have_http_status(:not_found)
    expect(other.reload.model_paused).to be(false)
    sign_in(model)
    get venue_models_path(venue)
    expect(response).to have_http_status(:not_found)
    post invite_all_venue_models_path(venue)
    expect(response).to have_http_status(:not_found)
  end

  it 'keeps private pause reasons out of model pages while allowing cancellation of retained bookings' do
    membership
    original = track_booking(BookingMutation.new(venue: venue, user: model).book(date: '2026-11-16'))
    manage_models
    post pause_venue_model_path(venue, membership), params: { reason: 'Private organizer note.' }
    sign_in(model)
    get venue_path(venue)
    expect(response.body).to include('posing access at this venue is paused', 'Cancel Booking')
    expect(response.body).not_to include('Private organizer note.', 'Change Date')
    get edit_venue_model_booking_path(venue, original)
    expect(response).to redirect_to(venue_path(venue))
    post cancel_venue_model_booking_path(venue, original), params: { reason: 'Travel.' }
    expect(original.reload.status).to eq('canceled')
  end

  it 'returns an emailed model to the scoped venue after login without granting access to another venue' do
    membership
    get venue_path(venue, booking_invitation: '1')
    expect(response).to redirect_to(new_session_path)
    sign_in(model)
    expect(response).to redirect_to(venue_path(venue))
    delete session_path
    get venue_path(create_venue, booking_invitation: '1')
    sign_in(model)
    expect(response).to redirect_to(root_path)
  end

  it 'validates pause explanations and leaves the previous grant intact' do
    membership
    manage_models
    post pause_venue_model_path(venue, membership), params: { reason: ' ' }
    follow_redirect!
    expect(response.body).to include('Provide a pause explanation')
    expect(membership.reload.model_paused).to be(false)
    expect(ModelBookingAccess.new(membership).allowed?).to be(true)
  end
end
