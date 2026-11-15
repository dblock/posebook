# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProgramCalendar, :aggregate_failures do
  include ActiveSupport::Testing::TimeHelpers

  let(:program) do
    Program.new(name: 'Community Program', time_zone: 'America/New_York', start_time: '18:30',
                venue: Venue.new(name: 'Community Venue', address: 'Example venue address'))
  end

  it 'uses the session-local date rather than the server date' do
    travel_to Time.utc(2026, 11, 17, 1) do
      calendar = described_class.new(program)
      expect(calendar.today).to eq(Date.new(2026, 11, 16))
      expect(calendar.blocked_reason(calendar.today)).to eq('Program has already started.')
      expect(calendar.blocked_reason(calendar.today + 1)).to eq('Not a scheduled day')
    end
  end

  it 'finds the next future session in the program time zone and skips sessions that have started' do
    travel_to Time.utc(2026, 11, 16, 23) do
      expect(described_class.new(program).next_session_date).to eq(Date.new(2026, 11, 16))
    end
    travel_to Time.utc(2026, 11, 16, 23, 30) do
      expect(described_class.new(program).next_session_date).to eq(Date.new(2026, 11, 23))
    end
    travel_to Time.utc(2026, 11, 17, 1) do
      expect(described_class.new(program).next_session_date).to eq(Date.new(2026, 11, 23))
    end
  end

  it 'skips sessions whose start or overnight end does not exist because of daylight saving' do
    travel_to Time.utc(2027, 3, 13, 15) do
      program.available_weekdays = ['6']
      program.start_time = '23:00'
      program.end_time = '02:30'
      expect(described_class.new(program).next_session_date).to eq(Date.new(2027, 3, 20))
      program.available_weekdays = ['0']
      program.start_time = '02:30'
      program.end_time = nil
      expect(described_class.new(program).next_session_date).to eq(Date.new(2027, 3, 21))
    end
  end

  it 'blocks past dates and dates beyond the calendar-month horizon' do
    travel_to Time.utc(2026, 11, 16, 15) do
      calendar = described_class.new(program)
      expect(calendar.last_date).to eq(Date.new(2027, 5, 16))
      expect(calendar.blocked_reason(Date.new(2026, 11, 9))).to eq('Outside booking window')
      expect(calendar.blocked_reason(Date.new(2027, 5, 17))).to eq('Outside booking window')
    end
  end

  it 'supports multiple weekdays and rejects invalid or empty weekday settings' do
    program.available_weekdays = ['', '1', '3', '3']
    expect(program).to be_valid
    expect(program.available_weekdays).to eq(%w[1 3])
    program.available_weekdays = ['7']
    expect(program).not_to be_valid
    program.available_weekdays = []
    expect(program).not_to be_valid
  end

  it 'opens the calendar at a future first bookable date and anchors the inclusive horizon there' do
    travel_to Time.utc(2026, 11, 16, 15) do
      program.first_bookable_date = Date.new(2027, 1, 1)
      program.available_weekdays = %w[0 1 2 3 4 5 6]
      calendar = described_class.new(program)
      expect(calendar.month).to eq(Date.new(2027, 1, 1))
      expect(calendar.blocked_reason(Date.new(2026, 12, 31))).to eq('Outside booking window')
      expect(calendar.blocked_reason(Date.new(2027, 1, 1))).to be_nil
      expect(calendar.blocked_reason(Date.new(2027, 7, 1))).to be_nil
      expect(calendar.blocked_reason(Date.new(2027, 7, 2))).to eq('Outside booking window')
      expect(described_class.new(program, month: '2027-07').month).to eq(Date.new(2027, 7, 1))
      expect(described_class.new(program, month: 'invalid').month).to eq(Date.new(2027, 1, 1))
      expect(described_class.new(program, month: '2026-11').month).to eq(Date.new(2026, 11, 1))
    end
  end

  it 'resumes a rolling horizon in the program time zone when the first bookable date is reached' do
    program.first_bookable_date = Date.new(2027, 1, 1)
    travel_to Time.utc(2027, 1, 2, 1) do
      calendar = described_class.new(program)
      expect(calendar.today).to eq(Date.new(2027, 1, 1))
      expect(calendar.last_date).to eq(Date.new(2027, 7, 1))
    end
    travel_to Time.utc(2027, 1, 2, 5) do
      expect(described_class.new(program).last_date).to eq(Date.new(2027, 7, 2))
    end
    program.first_bookable_date = nil
    travel_to Time.utc(2027, 1, 31, 15) do
      program.booking_horizon_months = 1
      expect(described_class.new(program).last_date).to eq(Date.new(2027, 2, 28))
    end
  end

  it 'bounds malformed and out-of-range month navigation' do
    travel_to Time.utc(2026, 11, 16, 15) do
      [nil, 'invalid', '2026-99', '2025-11', '2028-01'].each do |month|
        expect(described_class.new(program, month: month).month).to eq(Date.new(2026, 11, 1))
      end
      expect(described_class.new(program, month: '2027-01').month).to eq(Date.new(2027, 1, 1))
    end
  end

  it 'renders complete Sunday-to-Saturday weeks across year boundaries' do
    travel_to Time.utc(2026, 11, 16, 15) do
      weeks = described_class.new(program, month: '2027-01').weeks.to_a
      expect(weeks.first.first).to eq(Date.new(2026, 12, 27))
      expect(weeks.last.last).to eq(Date.new(2027, 2, 6))
      expect(weeks.map(&:length).uniq).to eq([7])
    end
  end

  it 'keeps civil weekdays stable across daylight saving changes' do
    travel_to Time.utc(2027, 3, 8, 15) do
      calendar = described_class.new(program)
      expect(calendar.blocked_reason(Date.new(2027, 3, 8))).to be_nil
      expect(calendar.blocked_reason(Date.new(2027, 3, 15))).to be_nil
      expect(calendar.blocked_reason(Date.new(2027, 3, 14))).to eq('Not a scheduled day')
    end
  end

  it 'reuses schedule times within one calendar, including absent end times' do
    travel_to Time.utc(2026, 11, 16, 15) do
      calendar = described_class.new(program)
      date = Date.new(2026, 11, 16)
      helper = Object.new.extend(ProgramCalendarHelper)
      allow(calendar.schedule).to receive(:starts_at).and_call_original
      allow(calendar.schedule).to receive(:ends_at).and_call_original
      2.times do
        expect(calendar.blocked_reason(date)).to be_nil
        expect(calendar.session_on?(date)).to be(true)
        expect(helper.scheduled_calendar_time(calendar, date)).to eq('6:30 PM')
        expect(calendar.ends_at(date)).to be_nil
      end
      expect(calendar.schedule).to have_received(:starts_at).with(date).once
      expect(calendar.schedule).to have_received(:ends_at).with(date).once
    end
  end

  it 'uses fresh times in a new calendar and does not cache daylight saving errors as values' do
    travel_to Time.utc(2027, 3, 8, 15) do
      program.available_weekdays = ['6']
      program.start_time = '23:00'
      program.end_time = '02:30'
      date = Date.new(2027, 3, 13)
      calendar = described_class.new(program)
      2.times do
        expect(calendar.blocked_reason(date)).to eq('End time unavailable because of daylight saving')
        expect(calendar.session_on?(date)).to be(false)
      end
      program.end_time = '03:30'
      fresh = described_class.new(program)
      expect(fresh.blocked_reason(date)).to be_nil
      expect(fresh.ends_at(date) - fresh.starts_at(date)).to eq(3.5.hours)
    end
  end

  it 'blocks nonexistent end times and calculates actual elapsed time across daylight saving' do
    travel_to Time.utc(2027, 3, 8, 15) do
      program.available_weekdays = ['6']
      program.start_time = '23:00'
      program.end_time = '02:30'
      calendar = described_class.new(program)
      expect(calendar.blocked_reason(Date.new(2027, 3, 13))).to eq('End time unavailable because of daylight saving')
      program.end_time = '03:30'
      schedule = ProgramSchedule.new(program)
      expect(schedule.ends_at(Date.new(2027, 3, 13)) - schedule.starts_at(Date.new(2027, 3, 13))).to eq(3.5.hours)
    end
  end
end
