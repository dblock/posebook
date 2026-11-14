# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProgramSchemaMigration, :aggregate_failures, :database do
  let(:client) do
    Mongoid.default_client.use("posebook_test_schema_#{SecureRandom.hex(8)}")
  end
  let(:owned_ids) { [] }

  after do
    client.database.collection_names.each do |name|
      client[name].find(_id: { '$in' => owned_ids }).delete_many
    end
    client.close
  end

  def seed_record(collection, attributes = {})
    id = BSON::ObjectId.new
    owned_ids << id
    client[collection].insert_one(attributes.merge('_id' => id))
    id
  end

  it 'converts the sole instance records and defaults without changing their IDs or administrator' do
    admin = seed_record('users', 'roles' => ['system_admin'], 'password_digest' => 'unchanged')
    venue = seed_record('venues', 'name' => 'Studio', 'session_schema_version' => 1)
    program = seed_record('drawing_sessions', 'venue_id' => venue, 'name' => 'Life Drawing',
                                              '_slugs' => %w[life-drawing earlier-name], 'model_pay' => BSON::Decimal128.new('140.35'),
                                              'schedule_revision' => 7)
    described_class.call(client)
    record = client['programs'].find(_id: program).first
    expect(record).to include('_id' => program, 'venue_id' => venue, 'name' => 'Life Drawing',
                              '_slugs' => %w[life-drawing earlier-name], 'pay' => BigDecimal('140.35'),
                              'program_label' => 'Session', 'participant_label' => 'Model', 'schedule_revision' => 7)
    expect(record).not_to have_key('model_pay')
    expect(client['venues'].find(_id: venue).first).to include('program_schema_version' => 1)
    expect(client['users'].find(_id: admin).first).to include('roles' => ['system_admin'],
                                                              'password_digest' => 'unchanged')
    expect(client.database.collection_names).not_to include('drawing_sessions')
  end

  context 'with related records' do
    let(:program) { seed_record('drawing_sessions') }
    let(:records) do
      membership = seed_record(
        'drawing_session_memberships',
        'drawing_session_id' => program, 'roles' => %w[session_coordinator model],
        'booking_invited_at' => Time.utc(2026, 11, 1), 'model_paused' => true, 'model_pause_reason' => 'Private pause.'
      )
      booking = seed_record(
        'model_bookings',
        'drawing_session_id' => program, 'reason' => 'Retained cancellation.',
        'status' => 'canceled', 'date' => Time.utc(2026, 11, 16), 'lock_version' => 4
      )
      history = seed_record(
        'history_trackers',
        'scope' => 'drawing_session_membership',
        'association_chain' => [{ 'name' => 'DrawingSessionMembership', 'id' => membership }],
        'original' => { 'model_paused' => false },
        'modified' => { 'model_paused' => true, 'model_pause_reason' => 'Private pause.',
                        'roles' => %w[session_coordinator model] }
      )
      { membership: membership, booking: booking, history: history,
        claim: seed_record('model_booking_claims', 'drawing_session_id' => program, 'model_booking_id' => booking),
        invitation: seed_record('model_invitations', 'drawing_session_id' => program, 'token_digest' => 'still-hashed'),
        exception: seed_record('drawing_session_schedule_exceptions',
                               'drawing_session_id' => program, 'reason' => 'Holiday.') }
    end

    before do
      records
      client['model_booking_claims'].indexes.create_one({ drawing_session_id: 1, user_id: 1 }, unique: true)
      described_class.call(client)
    end

    it 'retains booking snapshots, grants, pauses, tokens and schedule explanations' do
      expect(client['program_memberships'].find(_id: records[:membership]).first).to include(
        'program_id' => program, 'roles' => %w[program_coordinator participant], 'participant_paused' => true,
        'participant_pause_reason' => 'Private pause.', 'booking_invited_at' => Time.utc(2026, 11, 1)
      )
      expect(client['bookings'].find(_id: records[:booking]).first).to include(
        'program_id' => program, 'lock_version' => 4, 'date' => Time.utc(2026, 11, 16),
        'reason' => 'Retained cancellation.'
      )
      expect(client['booking_claims'].find(_id: records[:claim]).first).to include(
        'program_id' => program, 'booking_id' => records[:booking]
      )
      expect(client['participant_invitations'].find(_id: records[:invitation]).first).to include(
        'token_digest' => 'still-hashed'
      )
      expect(client['program_schedule_exceptions'].find(_id: records[:exception]).first).to include(
        'reason' => 'Holiday.'
      )
    end

    it 'converts audit scopes and fields and removes obsolete unique indexes' do
      expect(client['booking_claims'].indexes.to_a.pluck('key')).not_to include(
        'drawing_session_id' => 1, 'user_id' => 1
      )
      expect(client['history_trackers'].find(_id: records[:history]).first).to include(
        'scope' => 'program_membership',
        'association_chain' => [{ 'name' => 'ProgramMembership', 'id' => records[:membership] }],
        'original' => { 'participant_paused' => false },
        'modified' => { 'participant_paused' => true, 'participant_pause_reason' => 'Private pause.',
                        'roles' => %w[program_coordinator participant] }
      )
    end
  end

  it 'can repeat after a deployment or partially converted schema without overwriting configured labels' do
    program = seed_record('programs', 'model_pay' => 150, 'program_label' => 'Workshop',
                                      'participant_label' => 'Instructor')
    booking = seed_record('model_bookings', 'drawing_session_id' => program)
    2.times { described_class.call(client) }
    expect(client['programs'].find(_id: program).first).to include(
      'pay' => 150, 'program_label' => 'Workshop', 'participant_label' => 'Instructor'
    )
    expect(client['bookings'].find(_id: booking).first).to include('program_id' => program)
    expect(client['programs'].count_documents).to eq(1)
    expect(client['bookings'].count_documents).to eq(1)
  end

  it 'fails instead of overwriting an existing destination collection' do
    legacy = seed_record('drawing_sessions', 'name' => 'Original')
    current = seed_record('programs', 'name' => 'Other')
    expect { described_class.call(client) }.to raise_error(/programs already exists/)
    expect(client['drawing_sessions'].find(_id: legacy).first['name']).to eq('Original')
    expect(client['programs'].find(_id: current).first['name']).to eq('Other')
  end

  it 'leaves conflicting fields intact and can resume after the conflict is corrected' do
    program = seed_record('drawing_sessions', 'model_pay' => 100, 'pay' => 200)
    expect { described_class.call(client) }.to raise_error(/Conflicting legacy field model_pay and pay/)
    expect(client['programs'].find(_id: program).first).to include('model_pay' => 100, 'pay' => 200)
    client['programs'].find(_id: program).update_one('$unset' => { 'pay' => true })
    described_class.call(client)
    expect(client['programs'].find(_id: program).first).to include('pay' => 100)
  end
end
