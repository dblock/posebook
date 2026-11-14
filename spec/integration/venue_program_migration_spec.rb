# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VenueProgramMigration, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:venue) { create_venue(instagram_handle: '@coffee.shop') }
  let(:program) do
    create_program(venue: venue, id: venue.id, pay: 155, start_time: '19:00',
                   instructions: 'Legacy session notes.')
  end
  let(:participant) { create_user }
  let(:membership) { grant_participant_access(program, participant) }
  let(:booking) do
    membership
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-16'))
  end

  before do
    booking
    grant_coordinator_access(program, participant)
    membership.reload.update!(participant_paused: true, participant_pause_reason: 'Legacy pause.')
    store_legacy_membership
    [program, membership].each { |record| store_legacy_history(record) }
    legacy = program.as_document.slice(*described_class::SESSION_FIELDS)
    Venue.collection.find(_id: venue.id).update_one('$set' => legacy, '$unset' => { program_schema_version: true })
    Program.collection.find(_id: program.id).delete_one
    [booking, BookingClaim.find_by(booking_id: booking.id)].each do |record|
      record.class.collection.find(_id: record.id).update_one('$rename' => { program_id: 'venue_id' })
    end
  end

  after do
    VenueMembership.collection.find(_id: membership.id).delete_one
    Mongoid.default_client[:venue_schedule_exceptions].delete_many(venue_id: venue.id)
  end

  def store_legacy_membership
    attributes = membership.as_document
    attributes['venue_id'] = attributes.delete('program_id')
    attributes['roles'] = %w[manage_schedule participant]
    ProgramMembership.collection.find(_id: membership.id).delete_one
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
    value.to_s.sub(/\AProgram/, 'Venue').sub(/\Aprogram/, 'venue')
  end

  def store_legacy_exception
    record = track_record(ProgramScheduleException.create!(
                            program: program, date: Date.new(2026, 11, 23), mode: 'open',
                            start_time: '20:00', reason: 'Legacy exception.'
                          ))
    attributes = record.as_document
    attributes['venue_id'] = attributes.delete('program_id')
    store_legacy_history(record)
    Mongoid.default_client[:venue_schedule_exceptions].insert_one(attributes)
    ProgramScheduleException.collection.find(_id: record.id).delete_one
    record
  end

  it 'preserves IDs, booking snapshots, participant grants and pauses without promoting legacy coordinators' do
    original = booking.as_document
    described_class.call
    migrated = Program.find(program.id)
    expect(migrated.venue_id).to eq(venue.id)
    expect(migrated).to have_attributes(start_time: '19:00', pay: BigDecimal('155'))
    expect(venue.reload).to have_attributes(instagram_handle: 'coffee.shop', program_schema_version: 1)
    expect(membership.reload).to have_attributes(roles: %w[program_coordinator participant], participant_paused: true)
    expect(booking.reload.as_document.slice('date', 'starts_at', 'ends_at', 'lock_version'))
      .to eq(original.slice('date', 'starts_at', 'ends_at', 'lock_version'))
    expect(booking.program_id).to eq(program.id)
    expect(VenueMembership.where(venue_id: venue.id)).to be_empty
    expect(Venue.coordinated_by(participant)).to be_empty
    history = migrated.history_tracks.map(&:modified)
    expect(history).to include(hash_including('instructions' => 'Legacy session notes.'))
    expect(membership.history_tracks.map(&:modified)).to include(hash_including('participant_paused' => true))
  end

  it 'can run repeatedly without duplicating sessions or changing preserved data' do
    2.times { described_class.call }
    expect(Program.where(venue_id: venue.id).count).to eq(1)
    expect(ProgramMembership.where(program_id: program.id).count).to eq(1)
    expect(BookingClaim.find_by(booking_id: booking.id).program_id).to eq(program.id)
    expect(BookingClaim.collection.indexes.to_a.any? { |index| index['key'].key?('venue_id') }).to be(false)
  end

  it 'preserves usable invitation tokens and dated exceptions with their audit history' do
    invitation = create_participant_invitation(program, participant)
    ParticipantInvitation.collection.find(_id: invitation.id).update_one('$rename' => { program_id: 'venue_id' })
    exception = store_legacy_exception
    described_class.call
    expect(ParticipantInvitation.available(invitation.token).program_id).to eq(program.id)
    expect(exception.reload).to have_attributes(program_id: program.id, start_time: '20:00')
    expect(exception.history_tracks.map(&:modified)).to include(hash_including('reason' => 'Legacy exception.'))
  end

  it 'leaves new locations without sessions instead of treating them as legacy schedules' do
    location = create_venue
    described_class.call
    expect(Program.where(venue_id: location.id)).to be_empty
  end

  it 'rolls back the venue conversion when a dependent record cannot be moved' do
    collection = ProgramMembership.collection
    allow(ProgramMembership).to receive(:collection).and_return(collection)
    allow(collection).to receive(:insert_one).and_raise('Migration write failed')
    expect { described_class.call }.to raise_error('Migration write failed')
    expect(Program.where(id: program.id)).to be_empty
    expect(Venue.collection.find(_id: venue.id).first).not_to have_key('program_schema_version')
    expect(Booking.collection.find(_id: booking.id).first).to have_key('venue_id')
    expect(VenueMembership.collection.find(_id: membership.id).first).to be_present
  end
end
