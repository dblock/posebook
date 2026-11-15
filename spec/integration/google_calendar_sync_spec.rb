# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleCalendarSync, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program(start_time: '18:30', time_zone: 'America/New_York') }
  let(:organizer) { create_user }
  let(:participant) { create_user(instagram_handle: 'preview_model', instagram_tagging_allowed: true) }
  let(:api) { instance_spy(Google::Apis::CalendarV3::CalendarService) }
  let(:connection) do
    record = GoogleCalendarConnection.new(program: program, connected_by: organizer,
                                          calendar_id: 'preview-calendar@example.test')
    record.refresh_token = 'synthetic-refresh-token'
    track_record(record.tap(&:save!))
  end

  before do
    connection
    grant_coordinator_access(program, organizer)
    grant_participant_access(program, participant)
    auth = instance_double(Google::Auth::UserRefreshCredentials, :refresh_token= => nil)
    allow(GoogleCalendarConnection).to receive_messages(credentials: auth, service: api)
  end

  after { described_class.where(program_id: program.id).delete_all }

  def mutation
    BookingMutation.new(program: program, user: participant)
  end

  def book
    track_booking(mutation.book(date: '2026-11-23'))
  end

  it 'creates one private event with contact details, consented Instagram, attendees, and a one-hour fallback' do
    booking = book
    expect(described_class.process_next).to be_present
    expect(api).to have_received(:insert_event).once do |calendar, event, options|
      expect(calendar).to eq(connection.calendar_id)
      expect(event.id).to eq("posebook#{booking.id}")
      expect(event.description).to include(participant.phone, participant.email, 'Instagram tagging: Yes',
                                           '@preview_model')
      expect(event.attendees.map(&:email)).to contain_exactly(participant.email, organizer.email)
      expect(event).to have_attributes(visibility: 'private', guests_can_invite_others: false,
                                       guests_can_modify: false, guests_can_see_other_guests: true,
                                       location: program.venue.address)
      expect(Time.iso8601(event.start.date_time)).to eq(booking.scheduled_start)
      expect(Time.iso8601(event.end.date_time) - Time.iso8601(event.start.date_time)).to eq(1.hour)
      expect(event.reminders.use_default).to be(false)
      expect(options[:send_updates]).to eq('all')
    end
    expect(described_class.find(booking.id).reload.due_at).to be_nil
  end

  it 'starts invitations earlier while retaining actual booking and event end times' do
    program.update!(calendar_invitation_lead_minutes: 30, end_time: '21:00')
    booking = book
    original = booking.attributes.slice('starts_at', 'scheduled_ends_at', 'ends_at', 'lock_version', 'time_changes')
    described_class.process_next
    expect(api).to have_received(:insert_event) do |_, event, **|
      expect(Time.iso8601(event.start.date_time)).to eq(booking.scheduled_start - 30.minutes)
      expect(Time.iso8601(event.end.date_time)).to eq(booking.scheduled_ends_at)
      expect(event.description).to include('Program starts: Monday, November 23, 2026 at 6:30 PM EST')
    end
    expect(booking.reload.attributes.slice(*original.keys)).to eq(original)
  end

  it 'updates existing invitations with dated overrides without rewriting booking times' do
    ProgramScheduleMutation.new(program: program, user: organizer).call(
      date: '2026-11-23', mode: 'open', start_time: '20:00', end_time: '22:00', reason: 'Later session.'
    )
    booking = book
    described_class.process_next
    original = booking.attributes.slice('starts_at', 'scheduled_ends_at', 'ends_at', 'lock_version', 'time_changes')
    updates = []
    allow(api).to receive(:insert_event).and_raise(Google::Apis::ClientError.new('Conflict', status_code: 409))
    allow(api).to receive(:update_event) { |_, _, event, **| updates << event }
    ProgramSettingsUpdate.new(program: program, user: organizer).call(calendar_invitation_lead_minutes: 15)
    expect(described_class.find(booking.id).due_at).to be_present
    expect(updates).to be_empty
    described_class.process_next
    expect(Time.iso8601(updates.last.start.date_time)).to eq(booking.scheduled_start - 15.minutes)
    expect(Time.iso8601(updates.last.end.date_time)).to eq(booking.scheduled_ends_at)
    expect(updates.last.id).to eq("posebook#{booking.id}")
    expect(booking.reload.attributes.slice(*original.keys)).to eq(original)
  end

  it 'moves an existing invitation back to the session start when lead time returns to zero' do
    program.update!(calendar_invitation_lead_minutes: 15)
    booking = book
    described_class.process_next
    allow(api).to receive(:insert_event).and_raise(Google::Apis::ClientError.new('Conflict', status_code: 409))
    ProgramSettingsUpdate.new(program: program, user: organizer).call(calendar_invitation_lead_minutes: 0)
    described_class.process_next
    expect(api).to have_received(:update_event).with(
      connection.calendar_id, "posebook#{booking.id}",
      have_attributes(start: have_attributes(date_time: booking.scheduled_start.iso8601)), send_updates: 'all'
    )
  end

  it 'subtracts elapsed minutes across local date boundaries and daylight saving changes' do
    program.update!(start_time: '00:10', calendar_invitation_lead_minutes: 20)
    booking = book
    event = GoogleCalendarEvent.new(booking, connection).build
    expect(Time.iso8601(event.start.date_time)).to eq(Time.utc(2026, 11, 23, 4, 50))
    expect(Time.iso8601(event.end.date_time)).to eq(booking.scheduled_start + 1.hour)
    mutation.cancel(booking: booking, reason: 'Different date.')
    program.update!(start_time: '03:15', available_weekdays: ['0'], calendar_invitation_lead_minutes: 30)
    spring_booking = track_booking(mutation.book(date: '2027-03-14'))
    spring_event = GoogleCalendarEvent.new(spring_booking, connection).build
    expect(Time.iso8601(spring_event.start.date_time)).to eq(Time.utc(2027, 3, 14, 6, 45))
    expect(Time.iso8601(spring_event.end.date_time) - Time.iso8601(spring_event.start.date_time)).to eq(90.minutes)
    expect(spring_event.start.time_zone).to eq('America/New_York')
    expect(spring_booking.scheduled_start).to eq(Time.utc(2027, 3, 14, 7, 15))
  end

  it 'rolls back lead-time settings, audit entries, and queued changes if the outbox write fails' do
    booking = book
    described_class.process_next
    pending = described_class.find(booking.id)
    original_revision = pending.revision
    original_history_count = program.history_tracks.count
    allow(described_class).to receive(:enqueue).and_wrap_original do |enqueue, record, session:|
      enqueue.call(record, session: session)
      raise 'Synthetic outbox failure'
    end
    expect do
      ProgramSettingsUpdate.new(program: program, user: organizer).call(calendar_invitation_lead_minutes: 15)
    end.to raise_error(RuntimeError, 'Synthetic outbox failure')
    expect(program.reload.calendar_invitation_lead_minutes).to eq(0)
    expect(program.history_tracks.count).to eq(original_history_count)
    expect(pending.reload).to have_attributes(revision: original_revision, due_at: nil)
    expect(api).to have_received(:insert_event).once
  end

  it 'moves the same event on reschedule and sends a cancellation for the replacement' do
    program.update!(calendar_invitation_lead_minutes: 15)
    original = book
    described_class.process_next
    replacement = track_booking(mutation.change(booking: original, date: '2026-11-30', reason: 'Changed plans.'))
    allow(api).to receive(:insert_event).and_raise(Google::Apis::ClientError.new('Conflict', status_code: 409))
    described_class.process_next
    expect(api).to have_received(:update_event).with(
      connection.calendar_id, "posebook#{original.id}",
      have_attributes(start: have_attributes(date_time: (replacement.scheduled_start - 15.minutes).iso8601)),
      send_updates: 'all'
    )
    mutation.cancel(booking: replacement, reason: 'Canceled plans.')
    described_class.process_next
    expect(api).to have_received(:delete_event).with(connection.calendar_id, "posebook#{original.id}",
                                                     send_updates: 'all')
    expect(described_class.count).to eq(1)
    expect(described_class.first.booking_id).to eq(replacement.id)
  end

  it 'rolls back the outbox and booking if the booking transaction fails' do
    allow(BookingClaim).to receive(:create!).and_raise(BookingMutation::Conflict)
    expect { mutation.book(date: '2026-11-23') }.to raise_error(BookingMutation::Conflict)
    expect(Booking.where(program_id: program.id)).to be_empty
    expect(described_class.where(program_id: program.id)).to be_empty
    expect(api).not_to have_received(:insert_event)
  end

  it 'retains failed work for retry without persisting private provider error text' do
    booking = book
    allow(api).to receive(:insert_event).and_raise(Google::Apis::ServerError.new("Private #{participant.email}"))
    described_class.process_next
    pending = described_class.find(booking.id)
    expect(pending.last_error).to eq(Google::Apis::ServerError.name)
    expect(pending.due_at).to be > Time.current
    allow(api).to receive(:insert_event)
    travel 2.minutes
    described_class.process_next
    expect(pending.reload.due_at).to be_nil
    expect(pending.attempts).to eq(0)
  end

  it 'preserves a newer queued revision when a booking changes during a Google request' do
    booking = book
    allow(api).to receive(:insert_event) do
      mutation.cancel(booking: booking, reason: 'Changed during sync.')
    end
    described_class.process_next
    expect(described_class.find(booking.id).due_at).to be_present
    described_class.process_next
    expect(api).to have_received(:delete_event)
    expect(described_class.find(booking.id).due_at).to be_nil
  end

  it 'reclaims an expired worker lease and skips unchanged reconciled events' do
    booking = book
    described_class.find(booking.id).set(lease_until: 1.minute.ago, lease_token: 'abandoned')
    described_class.process_next
    described_class.reconcile
    described_class.process_next
    expect(api).to have_received(:insert_event).once
    expect(described_class.find(booking.id).due_at).to be_nil
  end

  it 'reveals guests on existing meetings through reconciliation without creating another event' do
    booking = book
    previous_payload = GoogleCalendarEvent.new(booking, connection).build
    previous_payload.guests_can_see_other_guests = false
    pending = described_class.find(booking.id)
    pending.set(fingerprint: pending.payload_fingerprint(connection, previous_payload), due_at: nil)
    allow(api).to receive(:insert_event).and_raise(Google::Apis::ClientError.new('Conflict', status_code: 409))
    described_class.reconcile
    described_class.process_next
    expect(api).to have_received(:update_event).with(
      connection.calendar_id, "posebook#{booking.id}",
      have_attributes(guests_can_see_other_guests: true, location: program.venue.address),
      send_updates: 'all'
    )
    described_class.reconcile
    described_class.process_next
    expect(api).to have_received(:update_event).once
    expect(pending.reload.due_at).to be_nil
  end

  it 'reflects schedule time edits and closures using the same event' do
    booking = book
    program.update!(end_time: '21:00')
    ProgramScheduleMutation.new(program: program, user: organizer).call(
      date: booking.date.iso8601, mode: 'open', start_time: '20:00', end_time: '22:00', reason: 'Later session.'
    )
    described_class.process_next
    expect(api).to have_received(:insert_event) do |_, event, **|
      expect(Time.iso8601(event.end.date_time) - Time.iso8601(event.start.date_time)).to eq(2.hours)
    end
    ProgramScheduleMutation.new(program: program, user: organizer).call(
      date: booking.date.iso8601, mode: 'closed', reason: 'Studio closed.'
    )
    described_class.process_next
    expect(api).to have_received(:delete_event)
  end

  it 'keeps disabled connections and private Instagram preferences out of delivery' do
    participant.update!(public_profile_private: true)
    booking = book
    event = GoogleCalendarEvent.new(booking, connection).build
    expect(event.description).to include('Instagram tagging: No')
    expect(event.description).not_to include('@preview_model')
    connection.update!(enabled: false)
    described_class.process_next
    expect(api).not_to have_received(:insert_event)
    expect(described_class.find(booking.id).due_at).to be_nil
  end

  it 'allows only one worker to claim a queued booking' do
    book
    results = 2.times.map { Thread.new { described_class.process_next } }.map(&:value)
    expect(results.compact.size).to eq(1)
    expect(api).to have_received(:insert_event).once
  end

  it 'delivers a booking through the shared Active Job worker' do
    booking = book
    job = GoogleCalendarSyncJob.perform_later
    track_record(QueuedJob.find(job.provider_job_id))
    expect(BackgroundWorker.build.work_off(1)).to eq([1, 0])
    expect(api).to have_received(:insert_event).once
    expect(described_class.find(booking.id).due_at).to be_nil
  end

  it 'runs periodic reconciliation as an Active Job' do
    booking = book
    described_class.process_next
    job = GoogleCalendarReconcileJob.perform_later
    track_record(QueuedJob.find(job.provider_job_id))
    expect(BackgroundWorker.build.work_off(1)).to eq([1, 0])
    expect(described_class.find(booking.id).due_at).to be_present
    described_class.process_next
    expect(api).to have_received(:insert_event).once
  end

  it 'completes cancellation when the remote event is already missing or canceled' do
    booking = book
    mutation.cancel(booking: booking, reason: 'Canceled before synchronization.')
    [404, 410].each do |status|
      described_class.enqueue(booking.reload)
      allow(api).to receive(:delete_event).and_raise(Google::Apis::ClientError.new('Gone', status_code: status))
      described_class.process_next
      expect(described_class.find(booking.id).due_at).to be_nil
    end
  end
end
