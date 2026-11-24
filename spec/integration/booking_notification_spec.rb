# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BookingNotification, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:program) { create_program(time_zone: 'America/New_York', start_time: '18:30', end_time: '21:00') }
  let(:participant) { create_user }
  let(:organizer) { create_user }
  let(:booking) do
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-23'))
  end

  before { grant_coordinator_access(program, organizer) }

  def notices(kind)
    BookingNotification.where(booking_id: booking.id, kind: kind)
  end

  def run_notifications
    BookingNotificationMaintenance.run
    deliver_emails
  end

  def clear_creation
    booking
    run_notifications
    ActionMailer::Base.deliveries.clear
  end

  it 'opens confirmation exactly at the preceding scheduled session end even when unbooked' do
    record = booking
    travel_to Time.utc(2026, 11, 17, 1, 59, 59)
    expect(record.confirmation_open?).to be(false)
    travel 1.second
    expect(record.confirmation_open?).to be(true)
    AttendanceMutation.new(program: program, user: participant).confirm(record.id, version: record.lock_version)
    expect(record.reload.attendance_confirmed?).to be(true)
  end

  it 'uses dated closures and openings and treats a missing end as local midnight' do
    booking
    track_record(ProgramScheduleException.create!(program: program, date: '2026-11-16', mode: 'closed',
                                                  reason: 'Holiday'))
    track_record(ProgramScheduleException.create!(program: program, date: '2026-11-18', mode: 'open',
                                                  start_time: '19:00', end_time: '22:00', reason: 'Special session'))
    expect(BookingNotificationTiming.new(booking).confirmation_opens_at).to eq(Time.utc(2026, 11, 19, 3))
    program.schedule_exceptions.where(date: Date.new(2026, 11, 18)).first.update!(end_time: nil)
    expect(BookingNotificationTiming.new(booking).confirmation_opens_at).to eq(Time.utc(2026, 11, 19, 5))
  end

  it 'uses a preceding booking saved end even after a later program time-zone change' do
    record = booking
    track_booking(Booking.create!(program: program, user: organizer, date: '2026-11-16',
                                  starts_at: Time.utc(2026, 11, 16, 23), time_zone: 'America/New_York',
                                  ends_at: Time.utc(2026, 11, 17, 4), scheduled_ends_at: Time.utc(2026, 11, 17, 4)))
    program.update!(time_zone: 'America/Los_Angeles')
    record.program = program
    expect(BookingNotificationTiming.new(record).confirmation_opens_at).to eq(Time.utc(2026, 11, 17, 4))
  end

  it 'supports configurable calendar-day timing across daylight saving' do
    program.update!(notification_settings: { 'confirmation_request' => {
                      'timing' => 'days_before', 'days_before' => 7, 'time' => '12:00'
                    } })
    travel_to Time.utc(2026, 10, 20, 12)
    grant_participant_access(program, participant)
    record = track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-02'))
    expect(BookingNotificationTiming.new(record).confirmation_opens_at).to eq(Time.utc(2026, 10, 26, 16))
  end

  %w[confirmation_reminder session_reminder coordinator_alert].each do |kind|
    it "delivers #{kind} at the inherited venue previous-session end only once" do
      program.venue.update!(notification_settings: {
                              'confirmation_request' => { 'enabled' => false },
                              kind => { 'enabled' => true, 'timing' => 'previous_session_end' }
                            })
      clear_creation
      travel_to Time.utc(2026, 11, 17, 1, 59, 59)
      run_notifications
      expect(notices(kind)).to be_empty
      travel 1.second
      2.times { run_notifications }
      recipient = kind == 'coordinator_alert' ? organizer : participant
      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[recipient.email]])
      expect(notices(kind).first).to have_attributes(state: 'sent', scheduled_for: Time.utc(2026, 11, 17, 2))
    end
  end

  it 'uses overnight exceptions and the saved time zone for inherited previous-session reminders' do
    program.venue.update!(notification_settings: { 'session_reminder' => { 'timing' => 'previous_session_end' } })
    record = booking
    track_record(ProgramScheduleException.create!(program: program, date: '2026-11-16', mode: 'closed',
                                                  reason: 'Closed'))
    exception = track_record(ProgramScheduleException.create!(
                               program: program, date: '2026-11-18', mode: 'open',
                               start_time: '22:00', end_time: '02:00', reason: 'Overnight'
                             ))
    program.update!(time_zone: 'America/Los_Angeles')
    record.program = program
    expect(BookingNotificationTiming.new(record).due_at('session_reminder')).to eq(Time.utc(2026, 11, 19, 7))
    exception.update!(end_time: nil)
    expect(BookingNotificationTiming.new(record).due_at('session_reminder')).to eq(Time.utc(2026, 11, 19, 5))
  end

  it 'allows a program to override venue session-end timing with a week-before checkpoint across daylight saving' do
    program.venue.update!(notification_settings: { 'session_reminder' => { 'timing' => 'previous_session_end' } })
    program.update!(notification_settings: {
                      'session_reminder' => { 'timing' => 'days_before', 'days_before' => 7, 'time' => '12:00' }
                    })
    travel_to Time.utc(2026, 10, 20, 12)
    grant_participant_access(program, participant)
    record = track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-11-02'))
    expect(BookingNotificationTiming.new(record).due_at('session_reminder')).to eq(Time.utc(2026, 10, 26, 16))
    expect(NotificationSetting.for(program.venue, 'session_reminder').timing).to eq('previous_session_end')
  end

  it 'does not replay a venue session-end reminder for a late booking or after the session starts' do
    program.venue.update!(notification_settings: { 'session_reminder' => { 'timing' => 'previous_session_end' } })
    travel_to Time.utc(2026, 11, 17, 15)
    clear_creation
    run_notifications
    expect(notices('session_reminder')).to be_empty
    expect(ActionMailer::Base.deliveries).to be_empty
    travel_to booking.scheduled_start
    run_notifications
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'sends creation mail once to the participant and deduplicated assigned coordinators' do
    grant_venue_access(program.venue, organizer)
    global_admin = create_user(roles: ['system_admin'])
    booking
    2.times { run_notifications }
    expect(ActionMailer::Base.deliveries.flat_map(&:to)).to contain_exactly(participant.email, organizer.email)
    expect(ActionMailer::Base.deliveries.flat_map(&:to)).not_to include(global_admin.email)
    expect(notices('booking_created').pluck(:recipient_id, :state)).to eq([[participant.id, 'sent']])
    expect(notices('coordinator_booking_created').pluck(:recipient_id, :state)).to eq([[organizer.id, 'sent']])
  end

  it 'addresses creation mail to the participant and a separate new-booking alert to coordinators' do
    booking
    run_notifications
    participant_mail = ActionMailer::Base.deliveries.find { |mail| mail.to == [participant.email] }
    organizer_mail = ActionMailer::Base.deliveries.find { |mail| mail.to == [organizer.email] }
    expect(participant_mail.subject).to include("You're booked")
    expect(participant_mail.text_part.body.decoded).to include("Hi #{participant.name}", 'Your session is booked')
    expect(organizer_mail.subject).to eq("New booking: #{participant.name} - Monday, November 23, 2026")
    expect(organizer_mail.text_part.body.decoded).to include("#{participant.name} booked a session at #{program.name}")
    expect(organizer_mail.text_part.body.decoded).not_to include('Hi ', 'Your session', 'confirm your attendance')
  end

  it 'includes coordinator phone numbers in participant contact details when available' do
    other_organizer = create_user(name: 'No Phone Organizer')
    grant_coordinator_access(program, other_organizer)
    other_organizer.set(phone: nil)
    booking
    run_notifications
    body = ActionMailer::Base.deliveries.find { |mail| mail.to == [participant.email] }.text_part.body.decoded
    expect(body).to include("#{organizer.name}: #{organizer.email} or #{organizer.display_phone}")
    expect(body).to match(/No Phone Organizer: #{Regexp.escape(other_organizer.email)}[.;]/)
  end

  it 'links booking emails to the calendar month containing the booking' do
    grant_participant_access(program, participant)
    record = track_booking(BookingMutation.new(program: program, user: participant).book(date: '2026-12-07'))
    run_notifications
    link = "/programs/#{program.to_param}/calendar?month=2026-12"
    expect(ActionMailer::Base.deliveries.map { |mail| mail.text_part.body.decoded }).to all(include(link))
    expect(described_class.where(booking_id: record.id).count).to eq(2)
  end

  it 'controls coordinator booking alerts separately from participant messages' do
    program.update!(notification_settings: { 'booking_created' => { 'enabled' => false } })
    booking
    run_notifications
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[organizer.email]])
    ActionMailer::Base.deliveries.clear
    BookingMutation.new(program: program, user: participant).cancel(booking: booking, reason: 'Private reason')
    run_notifications
    expect(ActionMailer::Base.deliveries.find { |mail| mail.to == [organizer.email] }.text_part.body.decoded)
      .to include("#{participant.name}'s booking at #{program.name} has been canceled")
  end

  it 'skips coordinator booking alerts when the coordinator disabled coordinator alerts' do
    organizer.update!(coordinator_notifications_enabled: false)
    booking
    run_notifications
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[participant.email]])
    expect(notices('coordinator_booking_created').pluck(:state)).to eq(['skipped'])
  end

  it 'does not send a coordinator alert to a coordinator who is the participant' do
    grant_participant_access(program, organizer)
    record = track_booking(BookingMutation.new(program: program, user: organizer).book(date: '2026-11-23'))
    run_notifications
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[organizer.email]])
    expect(described_class.where(booking_id: record.id).pluck(:kind)).to eq(['booking_created'])
  end

  it 'requests confirmation at opening and reminds only the unconfirmed participant five days before at noon' do
    clear_creation
    travel_to Time.utc(2026, 11, 17, 2)
    2.times { run_notifications }
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[participant.email]])
    expect(ActionMailer::Base.deliveries.last.subject).to include('Please confirm')
    ActionMailer::Base.deliveries.clear
    travel_to Time.utc(2026, 11, 18, 16, 59, 59)
    run_notifications
    expect(ActionMailer::Base.deliveries).to be_empty
    travel 1.second
    2.times { run_notifications }
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[participant.email]])
    expect(ActionMailer::Base.deliveries.last.subject).to include('Reminder to confirm')
  end

  it 'skips requests and unconfirmed reminders for confirmed attendance but sends the final reminder' do
    clear_creation
    travel_to Time.utc(2026, 11, 17, 2)
    AttendanceMutation.new(program: program, user: participant).confirm(booking.id, version: booking.lock_version)
    run_notifications
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[organizer.email]])
    ActionMailer::Base.deliveries.clear
    travel_to Time.utc(2026, 11, 18, 17)
    run_notifications
    expect(ActionMailer::Base.deliveries).to be_empty
    travel_to Time.utc(2026, 11, 22, 17)
    run_notifications
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[participant.email]])
    expect(ActionMailer::Base.deliveries.last.text_part.body.decoded).to include('Your attendance is confirmed.')
  end

  it 'suppresses duplicate late-booking messages and does not send a missed reminder backlog' do
    travel_to Time.utc(2026, 11, 18, 18)
    booking
    2.times { run_notifications }
    expect(ActionMailer::Base.deliveries.map(&:subject).grep(/Reminder|Please confirm/)).to be_empty
    expect(ActionMailer::Base.deliveries.find { |mail| mail.to == [participant.email] }.text_part.body.decoded)
      .to include('Please confirm your attendance')
    ActionMailer::Base.deliveries.clear
    travel_to Time.utc(2026, 11, 20, 18)
    run_notifications
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'rechecks preferences and cancellation before queued reminders are sent' do
    clear_creation
    travel_to Time.utc(2026, 11, 17, 2)
    BookingNotificationMaintenance.run
    participant.update!(booking_reminders_enabled: false)
    deliver_emails
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(notices('confirmation_request').first.state).to eq('skipped')
    participant.update!(booking_reminders_enabled: true)
    travel_to Time.utc(2026, 11, 18, 17)
    BookingNotificationMaintenance.run
    BookingMutation.new(program: program, user: participant).cancel(booking: booking, reason: 'Private reason')
    run_notifications
    expect(notices('confirmation_reminder').first.state).to eq('skipped')
    expect(ActionMailer::Base.deliveries.map(&:subject)).to all(include('Booking canceled'))
    expect(ActionMailer::Base.deliveries.map do |mail|
      mail.text_part.body.decoded
    end.join).not_to include('Private reason')
  end

  it 'sends one replacement notice instead of separate cancellation and creation messages' do
    clear_creation
    replacement = track_booking(BookingMutation.new(program: program, user: participant)
                                                .change(booking: booking, date: '2026-11-30', reason: 'Private notes'))
    run_notifications
    expect(ActionMailer::Base.deliveries.map(&:subject)).to contain_exactly(
      "Your session has changed: #{program.name}", "Booking changed: #{participant.name} - Monday, November 30, 2026"
    )
    expect(ActionMailer::Base.deliveries.map { |mail| mail.text_part.body.decoded })
      .to all(include('November 23', 'November 30'))
    expect(described_class.where(booking_id: replacement.id).pluck(:kind))
      .to contain_exactly('booking_changed', 'coordinator_booking_changed')
  end

  it 'retains failed delivery state and retries without losing the outbox' do
    booking
    BookingNotificationMaintenance.run
    allow(BookingNotificationMailer).to receive(:notify).and_raise(IOError)
    delivery = EmailDelivery.where(:resource_id.in => notices('booking_created').pluck(:id)).first
    # Delivering directly destroys the delivery, so cleanup can no longer find its queued job.
    track_record(QueuedJob.find(delivery.queued_job_id))
    expect { delivery.deliver }.to raise_error(IOError)
    expect(described_class.find(delivery.resource_id).state).to eq('failed')
    expect(EmailDelivery.where(id: delivery.id)).to exist
    allow(BookingNotificationMailer).to receive(:notify).and_call_original
    delivery.deliver
    expect(described_class.find(delivery.resource_id).state).to eq('sent')
  end

  it 'never queues a reminder once a session has started' do
    clear_creation
    travel_to booking.scheduled_start
    run_notifications
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'sends one coordinator change notice and separate participant notices when replacing a participant' do
    clear_creation
    other = create_user
    grant_participant_access(program, other)
    second_organizer = create_user
    grant_coordinator_access(program, second_organizer)
    replacement = OrganizerBookingMutation.new(program: program, user: organizer).update(
      booking.id, date: booking.date.iso8601, user_id: other.id.to_s, attendance: 'unconfirmed',
                  reason: 'Private replacement reason', lock_version: booking.lock_version
    )
    track_booking(replacement)
    run_notifications
    messages = ActionMailer::Base.deliveries
    expect(messages.size).to eq(3)
    expect(messages.find { |mail| mail.to == [participant.email] }.subject).to include('Booking canceled')
    expect(messages.find { |mail| mail.to == [other.email] }.subject).to include("You're booked")
    expect(messages.find { |mail| mail.to == [second_organizer.email] }.subject)
      .to eq("Booking changed: #{other.name} - Monday, November 23, 2026")
  end

  it 'queues location changes with the previous address and skips superseded notices' do
    booking
    old_address = program.venue.address
    VenueSettingsUpdate.new(venue: program.venue, user: create_user(roles: ['system_admin']))
                       .call(address: '123 New Studio Street')
    run_notifications
    expect(notices('booking_created').pluck(:state)).to eq(%w[skipped])
    expect(notices('coordinator_booking_created').pluck(:state)).to eq(%w[skipped])
    expect(ActionMailer::Base.deliveries.size).to eq(2)
    expect(ActionMailer::Base.deliveries.last.text_part.body.decoded).to include(old_address, '123 New Studio Street')
  end

  it 'sends a coordinator alert only once and rechecks assignment before delivery' do
    clear_creation
    program.update!(notification_settings: { 'coordinator_alert' => { 'enabled' => true } })
    travel_to Time.utc(2026, 11, 18, 17)
    BookingNotificationMaintenance.run
    grant_venue_access(program.venue, organizer)
    ProgramMembership.where(program_id: program.id, user_id: organizer.id).first.destroy!
    2.times { run_notifications }
    expect(notices('coordinator_alert').pluck(:state)).to eq(['sent'])
    expect(ActionMailer::Base.deliveries.count { |mail| mail.to == [organizer.email] }).to eq(1)
  end

  it 'discards queued attendance transitions that have been superseded' do
    clear_creation
    travel_to Time.utc(2026, 11, 17, 2)
    AttendanceMutation.new(program: program, user: participant).confirm(booking.id, version: booking.lock_version)
    OrganizerBookingMutation.new(program: program, user: organizer).update(
      booking.id, date: booking.date.iso8601, user_id: participant.id.to_s, attendance: 'unconfirmed',
                  reason: 'Recheck', lock_version: booking.reload.lock_version
    )
    run_notifications
    expect(notices('attendance_confirmed').pluck(:state)).to eq(['skipped'])
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([[participant.email]])
  end

  it 'rolls notification records back with an unsuccessful booking' do
    grant_participant_access(program, participant)
    allow(BookingClaim).to receive(:create!).and_raise(BookingMutation::Conflict)
    expect do
      BookingMutation.new(program: program, user: participant).book(date: '2026-11-23')
    end.to raise_error(BookingMutation::Conflict)
    expect(Booking.where(program_id: program.id)).to be_empty
    expect(described_class.where(recipient_id: participant.id)).to be_empty
  end

  it 'skips a queued reminder after its configured checkpoint changes' do
    clear_creation
    travel_to Time.utc(2026, 11, 18, 17)
    BookingNotificationMaintenance.run
    program.update!(notification_settings: { 'confirmation_reminder' => { 'time' => '14:00' } })
    deliver_emails
    expect(notices('confirmation_reminder').first.state).to eq('skipped')
    ActionMailer::Base.deliveries.clear
    travel 2.hours
    run_notifications
    expect(ActionMailer::Base.deliveries.map(&:subject)).to eq(
      ["Reminder to confirm: #{program.name} - Monday, November 23, 2026"]
    )
  end

  it 'does not duplicate a delayed booking message with a reminder sent on the same day' do
    booking
    travel_to Time.utc(2026, 11, 17, 2)
    run_notifications
    expect(ActionMailer::Base.deliveries.map(&:subject)).to contain_exactly(
      "You're booked: #{program.name} - Monday, November 23, 2026",
      "New booking: #{participant.name} - Monday, November 23, 2026"
    )
    expect(notices('confirmation_request').pluck(:state)).to eq(['skipped'])
    expect(ActionMailer::Base.deliveries.find { |mail| mail.to == [participant.email] }.text_part.body.decoded)
      .to include('Please confirm your attendance')
  end

  it 'includes organizer-confirmed replacement attendance in one change email per recipient' do
    clear_creation
    other_organizer = create_user
    grant_coordinator_access(program, other_organizer)
    replacement = OrganizerBookingMutation.new(program: program, user: organizer).update(
      booking.id, date: '2026-11-30', user_id: participant.id.to_s, attendance: 'confirmed',
                  reason: 'Moved with confirmation', lock_version: booking.lock_version
    )
    track_booking(replacement)
    run_notifications
    expect(ActionMailer::Base.deliveries.map(&:subject)).to contain_exactly(
      "Your session has changed: #{program.name}", "Booking changed: #{participant.name} - Monday, November 30, 2026"
    )
    expect(ActionMailer::Base.deliveries.find { |mail| mail.to == [participant.email] }.text_part.body.decoded)
      .to include('Your attendance is confirmed.')
  end
end
