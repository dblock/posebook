# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VenueCalendar, :aggregate_failures do
  include ActiveSupport::Testing::TimeHelpers

  let(:venue) { Venue.new(name: "Enoch's", address: 'New York') }

  it 'uses the venue-local date rather than the server date' do
    travel_to Time.utc(2026, 11, 17, 1) do
      calendar = described_class.new(venue)
      expect(calendar.today).to eq(Date.new(2026, 11, 16))
      expect(calendar.blocked_reason(calendar.today)).to be_nil
      expect(calendar.blocked_reason(calendar.today + 1)).to eq('Not a posing day')
    end
  end

  it 'blocks past dates and dates beyond the calendar-month horizon' do
    travel_to Time.utc(2026, 11, 16, 15) do
      calendar = described_class.new(venue)
      expect(calendar.last_date).to eq(Date.new(2027, 5, 16))
      expect(calendar.blocked_reason(Date.new(2026, 11, 9))).to eq('Outside booking window')
      expect(calendar.blocked_reason(Date.new(2027, 5, 17))).to eq('Outside booking window')
    end
  end

  it 'supports multiple weekdays and rejects invalid or empty weekday settings' do
    venue.available_weekdays = ['', '1', '3', '3']
    expect(venue).to be_valid
    expect(venue.available_weekdays).to eq(%w[1 3])
    venue.available_weekdays = ['7']
    expect(venue).not_to be_valid
    venue.available_weekdays = []
    expect(venue).not_to be_valid
  end

  it 'bounds malformed and out-of-range month navigation' do
    travel_to Time.utc(2026, 11, 16, 15) do
      [nil, 'invalid', '2026-99', '2025-11', '2028-01'].each do |month|
        expect(described_class.new(venue, month: month).month).to eq(Date.new(2026, 11, 1))
      end
      expect(described_class.new(venue, month: '2027-01').month).to eq(Date.new(2027, 1, 1))
    end
  end

  it 'renders complete Sunday-to-Saturday weeks across year boundaries' do
    travel_to Time.utc(2026, 11, 16, 15) do
      weeks = described_class.new(venue, month: '2027-01').weeks.to_a
      expect(weeks.first.first).to eq(Date.new(2026, 12, 27))
      expect(weeks.last.last).to eq(Date.new(2027, 2, 6))
      expect(weeks.map(&:length).uniq).to eq([7])
    end
  end

  it 'keeps civil weekdays stable across daylight saving changes' do
    travel_to Time.utc(2027, 3, 8, 15) do
      calendar = described_class.new(venue)
      expect(calendar.blocked_reason(Date.new(2027, 3, 8))).to be_nil
      expect(calendar.blocked_reason(Date.new(2027, 3, 15))).to be_nil
      expect(calendar.blocked_reason(Date.new(2027, 3, 14))).to eq('Not a posing day')
    end
  end
end
