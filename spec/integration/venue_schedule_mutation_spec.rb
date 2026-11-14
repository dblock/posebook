# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VenueScheduleMutation, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:venue) { create_venue }
  let(:admin) { create_user(roles: ['system_admin']) }
  let(:model) { create_user }

  def change_schedule(**attributes)
    values = { date: '2026-11-16', mode: 'open', start_time: '19:30', reason: 'Later drawing.' }.merge(attributes)
    track_record(described_class.new(venue: venue, user: admin).call(values))
  end

  def reserve(date = '2026-11-16')
    grant_model_access(venue, model)
    track_booking(BookingMutation.new(venue: venue, user: model).book(date: date))
  end

  it 'opens an extra weekday at its specified local time without changing other dates' do
    change_schedule(date: '2026-11-17', start_time: '14:00')
    calendar = VenueCalendar.new(venue)
    expect(calendar.blocked_reason(Date.new(2026, 11, 17))).to be_nil
    expect(calendar.blocked_reason(Date.new(2026, 11, 24))).to eq('Not a posing day')
    expect(reserve('2026-11-17').starts_at).to eq(Time.utc(2026, 11, 17, 19))
  end

  it 'closes an occupied regular date with its explanation and frees only the disposable claim' do
    booking = reserve
    change_schedule(mode: 'closed', reason: 'Thanksgiving holiday.')
    expect(booking.reload).to have_attributes(status: 'canceled', reason: 'Thanksgiving holiday.',
                                              changed_by_id: admin.id, date: Date.new(2026, 11, 16))
    expect(ModelBookingClaim.where(model_booking_id: booking.id)).to be_empty
    expect(venue.model_bookings.count).to eq(1)
    expect(VenueCalendar.new(venue).blocked_reason(booking.date)).to eq('Closed: Thanksgiving holiday.')
  end

  it 'changes one booked time while retaining the same booking and an attributed time-change ledger' do
    booking = reserve
    change_schedule
    expect(booking.reload).to have_attributes(status: 'confirmed', starts_at: Time.utc(2026, 11, 17, 0, 30))
    expect(booking.time_changes.last).to include('from' => Time.utc(2026, 11, 16, 23, 30),
                                                 'to' => Time.utc(2026, 11, 17, 0, 30),
                                                 'reason' => 'Later drawing.', 'changed_by_id' => admin.id)
    expect(ModelBookingClaim.find_by(model_booking_id: booking.id).user_id).to eq(model.id)
    expect(venue.model_bookings.count).to eq(1)
  end

  it 'restores regular scheduling without deleting the prior exception or its history' do
    first = change_schedule(mode: 'closed', reason: 'Holiday.')
    Current.set(user: admin) { change_schedule(mode: 'regular', reason: 'Venue reopened.') }
    expect(first.reload.mode).to eq('regular')
    expect(first.history_tracks.count).to eq(2)
    expect(first.history_tracks.last).to have_attributes(modifier_id: admin.id)
    expect(first.history_tracks.last.original['reason']).to eq('Holiday.')
    expect(VenueCalendar.new(venue).blocked_reason(first.date)).to be_nil
  end

  it 'cancels a one-off booking when restoring a normally unavailable weekday' do
    change_schedule(date: '2026-11-17')
    booking = reserve('2026-11-17')
    change_schedule(date: '2026-11-17', mode: 'regular', reason: 'Extra session withdrawn.')
    expect(booking.reload).to have_attributes(status: 'canceled', reason: 'Extra session withdrawn.')
  end

  it 'rejects invalid exceptions without changing the existing booked time' do
    booking = reserve
    [{ reason: ' ' }, { start_time: '25:30' }, { mode: 'invalid' }, { reason: 'x' * 201 },
     { date: '2026-11-09' }, { date: '2027-05-17' }].each do |attributes|
      expect(change_schedule(**attributes).errors).not_to be_empty
    end
    expect(venue.schedule_exceptions).to be_empty
    expect(booking.reload.starts_at).to eq(Time.utc(2026, 11, 16, 23, 30))
  end

  it 'rolls back closure, booking cancellation, and audit history if claim removal fails' do
    booking = reserve
    collection = ModelBookingClaim.collection
    view = collection.find(model_booking_id: booking.id)
    allow(ModelBookingClaim).to receive(:collection).and_return(collection)
    allow(collection).to receive(:find).and_call_original
    allow(collection).to receive(:find).with(model_booking_id: booking.id).and_return(view)
    allow(view).to receive(:delete_one).and_raise(Mongo::Error::OperationFailure, 'Claim removal failed')
    expect { change_schedule(mode: 'closed') }.to raise_error(Mongo::Error::OperationFailure)
    expect(booking.reload.status).to eq('confirmed')
    expect(venue.schedule_exceptions).to be_empty
    expect(HistoryTracker.where('modified.venue_id' => venue.id)).to be_empty
    expect(ModelBookingClaim.where(model_booking_id: booking.id).count).to eq(1)
  end

  it 'serializes a holiday closure with a simultaneous booking request' do
    grant_model_access(venue, model)
    operations = [
      Thread.new do
        track_booking(BookingMutation.new(venue: venue, user: model).book(date: '2026-11-16'))
      rescue BookingMutation::Invalid
        nil
      end,
      Thread.new { change_schedule(mode: 'closed', reason: 'Holiday.') }
    ]
    operations.each(&:value)
    expect(venue.model_bookings.where(status: 'confirmed')).to be_empty
    expect(ModelBookingClaim.where(venue_id: venue.id)).to be_empty
  end

  it 'honors daylight saving transitions and rejects nonexistent local start times' do
    change_schedule(date: '2027-03-07', start_time: '18:30')
    change_schedule(date: '2027-03-14', start_time: '18:30')
    schedule = VenueSchedule.new(venue)
    expect(schedule.starts_at(Date.new(2027, 3, 7))).to eq(Time.utc(2027, 3, 7, 23, 30))
    expect(schedule.starts_at(Date.new(2027, 3, 14))).to eq(Time.utc(2027, 3, 14, 22, 30))
    invalid = change_schedule(date: '2027-03-14', start_time: '02:30')
    expect(invalid.errors[:start_time]).not_to be_empty
    expect(venue.schedule_exceptions.find_by(date: Date.new(2027, 3, 14)).start_time).to eq('18:30')
  end

  it 'serializes a time override with a simultaneous booking at the effective new time' do
    grant_model_access(venue, model)
    operations = [
      Thread.new { track_booking(BookingMutation.new(venue: venue, user: model).book(date: '2026-11-16')) },
      Thread.new { change_schedule }
    ]
    operations.each(&:value)
    booking = venue.model_bookings.find_by(status: 'confirmed')
    expect(booking.starts_at).to eq(Time.utc(2026, 11, 17, 0, 30))
    expect(ModelBookingClaim.where(model_booking_id: booking.id).count).to eq(1)
  end

  it 'rolls back a regular-time change that would move an existing booking into a daylight saving gap' do
    venue.update!(available_weekdays: ['0'])
    booking = reserve('2027-03-14')
    result = VenueSettingsUpdate.new(venue: venue, user: admin).call(start_time: '02:30')
    expect(result.errors[:start_time]).not_to be_empty
    expect(venue.reload.start_time).to eq('18:30')
    expect(booking.reload.starts_at).to eq(Time.utc(2027, 3, 14, 22, 30))
    expect(booking.time_changes).to be_empty
  end

  it 'moves regular future bookings with the default time but leaves dated overrides unchanged' do
    regular = reserve
    change_schedule(date: '2026-11-23', start_time: '20:00')
    other = create_user
    grant_model_access(venue, other)
    overridden = track_booking(BookingMutation.new(venue: venue, user: other).book(date: '2026-11-23'))
    VenueSettingsUpdate.new(venue: venue, user: admin).call(start_time: '19:00')
    expect(regular.reload.starts_at).to eq(Time.utc(2026, 11, 17, 0))
    expect(regular.time_changes.last['reason']).to eq('Regular drawing time changed.')
    expect(overridden.reload.starts_at).to eq(Time.utc(2026, 11, 24, 1))
    expect(overridden.time_changes).to be_empty
  end
end
