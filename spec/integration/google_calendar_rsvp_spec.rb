# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleCalendarRsvp, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program }
  let(:organizer) { create_user }
  let(:participant) { create_user }
  let(:api) { instance_spy(Google::Apis::CalendarV3::CalendarService) }
  let(:connection) do
    record = GoogleCalendarConnection.new(program: program, connected_by: organizer,
                                          calendar_id: 'rsvp-calendar@example.test')
    record.refresh_token = 'synthetic-refresh-token'
    track_record(record.tap(&:save!))
  end

  def mutation
    BookingMutation.new(program: program, user: participant)
  end

  def booking
    @booking ||= track_booking(mutation.book(date: '2026-11-23'))
  end

  def sync
    @sync ||= begin
      booking
      GoogleCalendarSync.process_next
      GoogleCalendarSync.find(booking.id)
    end
  end

  before do
    connection
    grant_coordinator_access(program, organizer)
    grant_participant_access(program, participant)
    auth = instance_double(Google::Auth::UserRefreshCredentials, :refresh_token= => nil)
    allow(GoogleCalendarConnection).to receive_messages(credentials: auth, service: api)
    allow(api).to receive(:get_event).and_return(event('accepted'))
    sync
  end

  after { GoogleCalendarSync.where(program_id: program.id).delete_all }

  def event(status)
    guests = [
      Google::Apis::CalendarV3::EventAttendee.new(email: organizer.email, response_status: 'declined'),
      Google::Apis::CalendarV3::EventAttendee.new(email: participant.email.upcase, response_status: status)
    ]
    Google::Apis::CalendarV3::Event.new(attendees: guests)
  end

  def refresh
    described_class.new(sync.reload).refresh
  end

  def schedule
    RecurringJobSchedule.enqueue_due(Rails.application.config.x.recurring_jobs.slice(:GoogleCalendarRsvpPollJob))
    track_record(RecurringJobSchedule.find(GoogleCalendarRsvpPollJob.name))
    track_jobs
  end

  def track_jobs
    jobs = QueuedJob.where(queue: 'calendar')
    jobs.each { |job| track_record(job) }
  end

  def worker
    BackgroundWorker.build(queues: ['calendar'])
  end

  it 'reads only the model response without changing booking confirmation or inviting anyone again' do
    %w[needsAction accepted tentative declined].each do |status|
      allow(api).to receive(:get_event).and_return(event(status))
      refresh
      expect(sync.reload).to have_attributes(rsvp_status: status, rsvp_checked_at: Time.current,
                                             rsvp_booking_id: booking.id, rsvp_calendar_id: connection.calendar_id)
      expect(booking.reload.display_status).to eq('Booked')
      travel 12.hours
    end
    expect(api).to have_received(:get_event).with(connection.calendar_id, sync.event_id).exactly(4).times
    expect(api).to have_received(:insert_event).once
    expect(api).not_to have_received(:update_event)
    expect(api).not_to have_received(:delete_event)
  end

  it 'schedules response checks every 12 hours through the shared worker and skips fresh duplicate checks' do
    schedule
    expect(worker.work_off(1)).to eq([1, 0])
    track_jobs
    expect(worker.work_off(1)).to eq([1, 0])
    refresh
    expect(api).to have_received(:get_event).once
    travel 11.hours
    schedule
    expect(worker.work_off(1)).to eq([0, 0])
    travel 1.hour
    schedule
    expect(worker.work_off(1)).to eq([1, 0])
    track_jobs
    expect(worker.work_off(1)).to eq([1, 0])
    expect(api).to have_received(:get_event).twice
  end

  it 'skips bookings not yet synchronized, disabled connections, and connecting organizers without access' do
    sync.set(fingerprint: nil)
    refresh
    sync.set(fingerprint: sync.payload_fingerprint(connection))
    connection.update!(enabled: false)
    refresh
    connection.update!(enabled: true)
    organizer.update!(active: false)
    refresh
    organizer.update!(active: true)
    program.memberships.coordinators.first.pull(roles: 'program_coordinator')
    refresh
    expect(api).not_to have_received(:get_event)
    expect(sync.reload.rsvp_status).to be_nil
  end

  it 'does not poll canceled or completed bookings or enqueue ones not yet synchronized' do
    sync.set(fingerprint: nil)
    expect { described_class.enqueue_checks }.not_to change(QueuedJob, :count)
    sync.set(fingerprint: sync.payload_fingerprint(connection))
    now = Time.current
    travel_to booking.ends_at
    refresh
    expect { described_class.enqueue_checks }.not_to change(QueuedJob, :count)
    travel_to now
    mutation.cancel(booking: booking, reason: 'Canceled plans.')
    refresh
    expect(api).not_to have_received(:get_event)
  end

  it 'rejects responses from an old booking after rescheduling during the Google request' do
    replacement = nil
    allow(api).to receive(:get_event) do
      replacement = track_booking(mutation.change(booking: booking, date: '2026-11-30', reason: 'Moved.'))
      event('declined')
    end
    refresh
    expect(sync.reload).to have_attributes(booking_id: replacement.id, rsvp_status: nil, rsvp_checked_at: nil)
    expect(replacement.display_status).to eq('Booked')
  end

  it 'rejects responses when the destination calendar or model email changes during the Google request' do
    allow(api).to receive(:get_event) do
      connection.update!(calendar_id: 'different-calendar@example.test')
      event('declined')
    end
    refresh
    expect(sync.reload.rsvp_status).to be_nil
    connection.update!(calendar_id: 'rsvp-calendar@example.test')
    allow(api).to receive(:get_event) do
      participant.update!(email: 'different-model@example.test')
      event('declined')
    end
    refresh
    expect(sync.reload.rsvp_checked_at).to be_nil
  end

  it 'clears stale responses for missing attendees, unknown responses, or missing Google events' do
    refresh
    [Google::Apis::CalendarV3::Event.new, event('unknown'),
     Google::Apis::CalendarV3::Event.new(status: 'cancelled')].each do |response|
      travel 12.hours
      allow(api).to receive(:get_event).and_return(response)
      refresh
      expect(sync.reload.rsvp_status).to be_nil
    end
    [404, 410].each do |status|
      travel 12.hours
      allow(api).to receive(:get_event).and_raise(Google::Apis::ClientError.new('Gone', status_code: status))
      refresh
      expect(sync.reload).to have_attributes(rsvp_status: nil, rsvp_checked_at: Time.current)
    end
    expect(booking.reload.display_status).to eq('Booked')
  end

  it 'retries provider failures without leaking private errors or replacing the last successful response' do
    refresh
    checked_at = sync.reload.rsvp_checked_at
    travel 12.hours
    allow(api).to receive(:get_event).and_raise(Google::Apis::ServerError.new("Private #{participant.email} token"))
    job = GoogleCalendarRsvpJob.perform_later(sync.id.to_s)
    queued = track_record(QueuedJob.find(job.provider_job_id))
    expect(worker.work_off(1)).to eq([0, 1])
    expect(queued.reload).to have_attributes(attempts: 1, last_error: Google::Apis::ServerError.name)
    expect(sync.reload).to have_attributes(rsvp_status: 'accepted', rsvp_checked_at: checked_at)
    allow(api).to receive(:get_event).and_return(event('declined'))
    travel_to queued.run_at + 1.second
    expect(worker.work_off(1)).to eq([1, 0])
    expect(sync.reload.rsvp_status).to eq('declined')
  end
end
