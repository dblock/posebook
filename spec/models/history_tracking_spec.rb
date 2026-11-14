# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HistoryTracking, :aggregate_failures, :database do
  it 'stores user creation and profile/access changes without authentication material' do
    user = create_user
    user.update!(name: 'Updated Participant', phone: '+12125551234', roles: ['system_admin'],
                 password: 'a replacement password for history',
                 password_confirmation: 'a replacement password for history',
                 session_version: 'private session', password_reset_digest: 'private digest',
                 email_change_digest: 'private confirmation', pending_email: 'pending@example.test')
    change = user.history_tracks.last
    expect(change.original['name']).to eq('Test Participant')
    expect(change.modified).to include('name' => 'Updated Participant', 'phone' => '+12125551234',
                                       'roles' => ['system_admin'])
    expect(user.history_tracks.to_a.to_json).not_to include('password', 'digest', 'session_version', 'pending_email',
                                                            'private session', 'private digest', 'private confirmation')
    expect(user.history_tracks.count).to eq(2)
    expect(change).to have_attributes(action: 'update', version: user.reload.version)
  end

  it 'records all session settings including slug history and blank changes' do
    program = create_program
    previous_slug = program.slug
    program.update!(
      name: 'Booking Program', custom_slug: 'booking', time_zone: 'America/Los_Angeles',
      pay: 150, instructions: 'Arrive early.', booking_horizon_months: 9, available_weekdays: ['3']
    )
    change = program.history_tracks.last
    expect(change.modified.keys).to include('name', 'custom_slug', '_slugs', 'time_zone', 'pay',
                                            'instructions', 'booking_horizon_months', 'available_weekdays')
    expect(change.original['_slugs']).to eq([previous_slug])
    program.update!(instructions: '')
    expect(program.history_tracks.last.modified).to include('instructions' => '')
  end

  it 'does not add history for failed, unchanged, or authentication-only saves' do
    user = create_user
    original_count = user.history_tracks.count
    expect(user.update(name: '')).to be(false)
    user.reload.save!
    user.update!(session_version: 'another private session', password_reset_digest: 'another private digest')
    expect(user.history_tracks.count).to eq(original_count)
  end

  it 'stores actor changes without reusing a previous actor for later system writes' do
    actor = create_user
    program = create_program
    Current.set(user: actor) { program.update!(instructions: 'Changed by an organizer.') }
    expect(program.history_tracks.last.modifier_id).to eq(actor.id)
    program.update!(instructions: 'Changed by a system task.')
    expect(program.history_tracks.last.modifier_id).to be_nil
  end

  it 'retains a deletion entry with the actor while keeping secrets out of the snapshot' do
    actor = create_user
    user = create_user
    Current.set(user: actor) { user.destroy }
    deletion = user.history_tracks.last
    expect(deletion).to have_attributes(action: 'destroy', modifier_id: actor.id)
    expect(deletion.original).to include('email' => user.email, 'name' => user.name)
    expect(deletion.original.keys.grep(/password|digest|session|token/)).to be_empty
  end

  it 'commits deactivation and reactivation with their history' do
    user = create_user
    Current.set(user: user) { user.deactivate }
    expect(user.history_tracks.last).to have_attributes(modified: { 'active' => false }, modifier_id: user.id)
    user.reactivate
    expect(user.history_tracks.last.modified).to eq('active' => true)
    expect(user.history_tracks.count).to eq(3)
  end

  it 'does not deactivate when its history cannot be stored' do
    user = create_user
    allow(HistoryTracker).to receive(:create!).and_raise(Mongo::Error::OperationFailure, 'History write failed')
    expect { user.deactivate }.to raise_error(Mongo::Error::OperationFailure)
    expect(user.reload).to be_active
    expect(user.history_tracks.count).to eq(1)
  end

  it 'rolls back both account and history writes when their transaction cannot commit' do
    user = create_user
    allow(User).to receive(:with_session).and_wrap_original do |original, &operation|
      original.call do |session|
        allow(session).to receive(:commit_transaction).and_raise(Mongo::Error::OperationFailure, 'Commit failed')
        operation.call(session)
      end
    end
    expect { user.deactivate }.to raise_error(Mongo::Error::OperationFailure)
    expect(user.reload).to be_active
    expect(user.history_tracks.count).to eq(1)
  end
end
