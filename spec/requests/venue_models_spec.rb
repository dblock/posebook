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
    get venue_models_path(venue)
    expect(response.parsed_body.at_css('.model-counts').text.squish)
      .to eq("4 total models \u00b7 1 available \u00b7 1 booked \u00b7 1 paused \u00b7 1 inactive")
    expect(response.parsed_body.at_css('main form button').text).to eq('Invite All Available Models (1)')
    post invite_all_venue_models_path(venue)
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[available.user.email]])
    follow_redirect!
    expect(response.body).to include('3 booked, paused, or inactive models skipped')
  end

  context 'with a paginated roster' do
    let(:members) { Array.new(3) { |index| grant_model_access(venue, create_user(name: "Roster Model #{index}")) } }

    before do
      stub_const('VenueModelRoster::PER_PAGE', 2)
      members
      manage_models
    end

    it 'orders pages consistently and shows venue-wide counts and navigation' do
      get venue_models_path(venue)
      expect(response.parsed_body.css('tr[data-membership]').pluck('data-membership'))
        .to eq(members.first(2).map { |item| item.id.to_s })
      expect(response.parsed_body.text).to include('3 total models', '3 available', 'Invite All Available Models (3)')
      expect(response.parsed_body.at_css('a[rel="next"]')['href']).to eq(venue_models_path(venue, page: 2))
      expect(response.parsed_body.at_css('a[rel="prev"]')).to be_nil
      get venue_models_path(venue, page: 2)
      expect(response.parsed_body.css('tr[data-membership]').pluck('data-membership')).to eq([members.last.id.to_s])
      expect(response.parsed_body.at_css('a[rel="prev"]')['href']).to eq(venue_models_path(venue, page: 1))
      expect(response.parsed_body.at_css('a[rel="next"]')).to be_nil
    end

    it 'invites all pages and retains the current page after individual and bulk actions' do
      post invite_all_venue_models_path(venue, page: 2)
      expect(response).to redirect_to(venue_models_path(venue, page: 2))
      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to match_array(members.map { |item| item.user.email })
      post pause_venue_model_path(venue, members.last, page: 2), params: { reason: 'Travel.' }
      expect(response).to redirect_to(venue_models_path(venue, page: 2))
      follow_redirect!
      expect(response.parsed_body.text).to include('3 total models', '2 available', '1 paused')
      expect(response.parsed_body.at_css("tr[data-membership='#{members.last.id}'] summary").text).to eq('Pause note')
    end

    it 'clamps missing, invalid, and out-of-range pages to valid bounds' do
      get venue_models_path(venue, page: 999)
      expect(response.body).to include('Page 2 of 2')
      get venue_models_path(venue, page: -1)
      expect(response.body).to include('Page 1 of 2')
      get venue_models_path(venue, page: 'invalid')
      expect(response.body).to include('Page 1 of 2')
    end
  end

  it 'handles an empty roster without pagination or an enabled bulk action' do
    manage_models
    get venue_models_path(venue, page: 999)
    expect(response.parsed_body.text).to include('0 total models', '0 available', 'No models assigned.')
    expect(response.parsed_body.at_css('form button[disabled]').text).to eq('Invite All Available Models (0)')
    expect(response.parsed_body.at_css('nav[aria-label="Model pages"]')).to be_nil
    membership.update!(model_paused: true, model_pause_reason: 'Taking a break.')
    get venue_models_path(venue)
    expect(response.parsed_body.text).to include('1 total models', '0 available', '1 paused')
    expect(response.parsed_body.at_css('form button[disabled]').text).to eq('Invite All Available Models (0)')
  end

  it 'counts overlapping statuses once and treats completed or canceled bookings as available' do
    completed = membership
    past = track_booking(BookingMutation.new(venue: venue, user: model).book(date: '2026-11-16'))
    canceled_user = create_user
    grant_model_access(venue, canceled_user)
    canceled = track_booking(BookingMutation.new(venue: venue, user: canceled_user).book(date: '2026-11-23'))
    BookingMutation.new(venue: venue, user: canceled_user).cancel(booking: canceled, reason: 'Travel.')
    inactive = grant_model_access(venue, create_user(active: false))
    inactive.update!(model_paused: true, model_pause_reason: 'Inactive and paused.')
    manage_models

    travel_to(past.ends_at + 1.second)
    get venue_models_path(venue)
    expect(response.parsed_body.at_css('.model-counts').text.squish)
      .to eq("3 total models \u00b7 2 available \u00b7 0 booked \u00b7 0 paused \u00b7 1 inactive")
    expect(response.parsed_body.at_css("tr[data-membership='#{completed.id}']").text)
      .to include('Invitation required', 'Invite to Book')
  end

  it 'keeps granted permission and reports failed email rather than claiming delivery succeeded' do
    membership
    manage_models
    error = IOError.new('SMTP failed')
    allow(BookingInvitationMailer).to receive(:invite).and_raise(error)
    allow(NewRelic::Agent).to receive(:notice_error)
    post invite_venue_model_path(venue, membership)
    follow_redirect!
    expect(response.body).to include('Booking enabled, but invitation email could not be sent')
    expect(ModelBookingAccess.new(membership.reload).allowed?).to be(true)
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(NewRelic::Agent).to have_received(:notice_error).with(error).once
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
    post cancel_venue_model_booking_path(venue, original),
         params: { reason: 'Travel.', booking_version: original.lock_version }
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
