# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AttendanceMutation, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  let(:venue) { create_venue }
  let(:model) { create_user }
  let(:booking) do
    grant_model_access(venue, model)
    track_booking(BookingMutation.new(venue: venue, user: model).book(date: '2026-11-23'))
  end

  def confirm
    described_class.new(venue: venue, user: model).confirm(booking.id)
  end

  it 'uses saved local calendar dates across daylight saving and later venue time-zone changes' do
    travel_to Time.utc(2026, 10, 24, 15)
    grant_model_access(venue, model)
    record = track_booking(BookingMutation.new(venue: venue, user: model).book(date: '2026-11-02'))
    venue.update!(time_zone: 'America/Los_Angeles')
    travel_to Time.utc(2026, 10, 26, 3, 59, 59)
    expect(record.confirmation_open?).to be(false)
    travel_to Time.utc(2026, 10, 26, 4)
    expect(record.confirmation_open?).to be(true)
    travel_to Time.utc(2026, 10, 28, 4)
    expect(record.rescheduling_locked?).to be(true)
    expect(record.scheduled_start).to eq(Time.utc(2026, 11, 2, 23, 30))
  end

  it 'closes confirmation at the drawing start but retains a previous confirmation' do
    record = booking
    travel_to record.scheduled_start
    expect { confirm }.to raise_error(BookingMutation::Invalid, /closes when it starts/)
    expect(record.reload.attendance_confirmed?).to be(false)
  end

  it 'retains a model confirmation on the old date and starts a rescheduled booking unconfirmed' do
    record = booking
    travel_to Time.utc(2026, 11, 16, 15)
    confirm
    replacement = track_booking(BookingMutation.new(venue: venue, user: model)
                                               .change(booking: record, date: '2026-11-30', reason: 'Travel.'))
    expect(record.reload.attendance_confirmed?).to be(true)
    expect(record.attendance_changes.last['changed_by_id']).to eq(model.id)
    expect(replacement.attendance_confirmed?).to be(false)
  end

  it 'rechecks membership and account activity inside the transaction even for loaded users' do
    record = booking
    travel_to Time.utc(2026, 11, 16, 15)
    User.find(model.id).update!(active: false)
    expect { confirm }.to raise_error(BookingMutation::Invalid, /model invitation/)
    expect(record.reload.attendance_confirmed?).to be(false)
  end

  it 'serializes competing confirmations without duplicating attendance history' do
    record = booking
    travel_to Time.utc(2026, 11, 16, 15)
    2.times.map { Thread.new { confirm } }.each(&:value)
    expect(record.reload.attendance_changes.size).to eq(1)
  end

  it 'serializes confirmation with a reschedule without confirming the replacement accidentally' do
    record = booking
    travel_to Time.utc(2026, 11, 16, 15)
    confirming = Thread.new do
      confirm
    rescue Mongoid::Errors::DocumentNotFound
      nil
    end
    replacement = track_booking(BookingMutation.new(venue: venue, user: model)
                                               .change(booking: record, date: '2026-11-30', reason: 'Travel.'))
    confirming.value
    expect(record.reload.status).to eq('rescheduled')
    expect(replacement.attendance_confirmed?).to be(false)
    expect(record.attendance_changes.size).to be <= 1
  end
end
