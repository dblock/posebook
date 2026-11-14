# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VenueSessionMigration, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:venue) { create_venue(instagram_handle: '@coffee.shop') }
  let(:program) do
    create_drawing_session(venue: venue, id: venue.id, model_pay: 155, start_time: '19:00',
                           instructions: 'Legacy session notes.')
  end
  let(:model) { create_user }
  let(:membership) { grant_model_access(program, model) }
  let(:booking) do
    membership
    track_booking(BookingMutation.new(drawing_session: program, user: model).book(date: '2026-11-16'))
  end

  before do
    booking
    grant_coordinator_access(program, model)
    membership.reload.update!(model_paused: true, model_pause_reason: 'Legacy pause.')
    store_legacy_membership
    [program, membership].each { |record| store_legacy_history(record) }
    legacy = program.as_document.slice(*described_class::SESSION_FIELDS)
    Venue.collection.find(_id: venue.id).update_one('$set' => legacy, '$unset' => { session_schema_version: true })
    DrawingSession.collection.find(_id: program.id).delete_one
    [booking, ModelBookingClaim.find_by(model_booking_id: booking.id)].each do |record|
      record.class.collection.find(_id: record.id).update_one('$rename' => { drawing_session_id: 'venue_id' })
    end
  end

  after do
    VenueMembership.collection.find(_id: membership.id).delete_one
    Mongoid.default_client[:venue_schedule_exceptions].delete_many(venue_id: venue.id)
  end

  def store_legacy_membership
    attributes = membership.as_document
    attributes['venue_id'] = attributes.delete('drawing_session_id')
    attributes['roles'] = %w[manage_schedule model]
    DrawingSessionMembership.collection.find(_id: membership.id).delete_one
    VenueMembership.collection.insert_one(attributes)
  end

  def store_legacy_history(record)
    record.history_tracks.each do |history|
      changes = { scope: legacy_scope(history.scope),
                  association_chain: history.association_chain.map do |part|
                    part.merge('name' => legacy_scope(part['name']))
                  end }
      HistoryTracker.collection.find(_id: history.id).update_one('$set' => changes)
    end
  end

  def legacy_scope(value)
    value.to_s.sub(/\ADrawingSession/, 'Venue').sub(/\Adrawing_session/, 'venue')
  end

  def store_legacy_exception
    record = track_record(DrawingSessionScheduleException.create!(
                            drawing_session: program, date: Date.new(2026, 11, 23), mode: 'open',
                            start_time: '20:00', reason: 'Legacy exception.'
                          ))
    attributes = record.as_document
    attributes['venue_id'] = attributes.delete('drawing_session_id')
    store_legacy_history(record)
    Mongoid.default_client[:venue_schedule_exceptions].insert_one(attributes)
    DrawingSessionScheduleException.collection.find(_id: record.id).delete_one
    record
  end

  it 'preserves IDs, booking snapshots, model grants and pauses without promoting legacy coordinators' do
    original = booking.as_document
    described_class.call
    migrated = DrawingSession.find(program.id)
    expect(migrated.venue_id).to eq(venue.id)
    expect(migrated).to have_attributes(start_time: '19:00', model_pay: BigDecimal('155'))
    expect(venue.reload).to have_attributes(instagram_handle: 'coffee.shop', session_schema_version: 1)
    expect(membership.reload).to have_attributes(roles: %w[session_coordinator model], model_paused: true)
    expect(booking.reload.as_document.slice('date', 'starts_at', 'ends_at', 'lock_version'))
      .to eq(original.slice('date', 'starts_at', 'ends_at', 'lock_version'))
    expect(booking.drawing_session_id).to eq(program.id)
    expect(VenueMembership.where(venue_id: venue.id)).to be_empty
    expect(Venue.coordinated_by(model)).to be_empty
    history = migrated.history_tracks.map(&:modified)
    expect(history).to include(hash_including('instructions' => 'Legacy session notes.'))
    expect(membership.history_tracks.map(&:modified)).to include(hash_including('model_paused' => true))
  end

  it 'can run repeatedly without duplicating sessions or changing preserved data' do
    2.times { described_class.call }
    expect(DrawingSession.where(venue_id: venue.id).count).to eq(1)
    expect(DrawingSessionMembership.where(drawing_session_id: program.id).count).to eq(1)
    expect(ModelBookingClaim.find_by(model_booking_id: booking.id).drawing_session_id).to eq(program.id)
    expect(ModelBookingClaim.collection.indexes.to_a.any? { |index| index['key'].key?('venue_id') }).to be(false)
  end

  it 'preserves usable invitation tokens and dated exceptions with their audit history' do
    invitation = create_model_invitation(program, model)
    ModelInvitation.collection.find(_id: invitation.id).update_one('$rename' => { drawing_session_id: 'venue_id' })
    exception = store_legacy_exception
    described_class.call
    expect(ModelInvitation.available(invitation.token).drawing_session_id).to eq(program.id)
    expect(exception.reload).to have_attributes(drawing_session_id: program.id, start_time: '20:00')
    expect(exception.history_tracks.map(&:modified)).to include(hash_including('reason' => 'Legacy exception.'))
  end

  it 'leaves new locations without sessions instead of treating them as legacy schedules' do
    location = create_venue
    described_class.call
    expect(DrawingSession.where(venue_id: location.id)).to be_empty
  end

  it 'rolls back the venue conversion when a dependent record cannot be moved' do
    collection = DrawingSessionMembership.collection
    allow(DrawingSessionMembership).to receive(:collection).and_return(collection)
    allow(collection).to receive(:insert_one).and_raise('Migration write failed')
    expect { described_class.call }.to raise_error('Migration write failed')
    expect(DrawingSession.where(id: program.id)).to be_empty
    expect(Venue.collection.find(_id: venue.id).first).not_to have_key('session_schema_version')
    expect(ModelBooking.collection.find(_id: booking.id).first).to have_key('venue_id')
    expect(VenueMembership.collection.find(_id: membership.id).first).to be_present
  end
end
