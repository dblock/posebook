# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DateDisplayHelper, :aggregate_failures, type: :helper do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 16, 15, 15)) { example.run } }

  def rendered(value, **)
    html = helper.render('shared/date', value: value, zone: 'America/New_York', **)
    Nokogiri::HTML.fragment(html).at_css('time')
  end

  { -7 => 'Nov 9', -6 => 'Last Tue', -2 => 'Last Sat', -1 => 'Yesterday', 0 => 'Today',
    1 => 'Tomorrow', 2 => 'Next Wed', 6 => 'Next Sun', 7 => 'Nov 23' }.each do |offset, label|
    it "labels #{offset} calendar days away as #{label}" do
      expect(rendered(Date.new(2026, 11, 16) + offset, format: :compact).text).to eq(label)
    end
  end

  it 'uses longer weekday labels in roomier locations' do
    expect(rendered(Date.new(2026, 11, 18)).text).to eq('Next Wednesday')
    expect(rendered(Date.new(2026, 12, 16)).text).to eq('Wed, Dec 16')
  end

  it 'omits only the current year from absolute dates' do
    expect(rendered(Date.new(2026, 12, 16), format: :compact).text).to eq('Dec 16')
    expect(rendered(Date.new(2025, 12, 16), format: :compact).text).to eq('Dec 16, 2025')
    expect(rendered(Date.new(2027, 12, 16)).text).to eq('Thu, Dec 16, 2027')
  end

  it 'compares years in the supplied zone rather than the server zone' do
    travel_to Time.utc(2026, 12, 31, 23, 30)
    value = Date.new(2026, 12, 16)
    expect(rendered(value, zone: 'UTC', format: :compact).text).to eq('Dec 16')
    expect(rendered(value, zone: 'Asia/Tokyo', format: :compact).text).to eq('Dec 16, 2026')
  end

  it 'keeps complete hover dates with local time zones and precise machine values' do
    date = rendered(Time.iso8601('2026-12-16T05:25:43.123456789Z'), format: :compact)
    full = 'Wednesday, December 16, 2026 at 12:25 AM EST'
    expect(date.at_css('.date-display-label').text).to eq('Dec 16')
    expect(date.at_css('.date-display-clock').text).to eq(' at 12:25 AM')
    expect(date['title']).to eq(full)
    expect(date['aria-label']).to eq(full)
    expect(date['datetime']).to eq('2026-12-16T00:25:43.123456789-05:00')
    expect(date['tabindex']).to be_nil
  end

  it 'converts DateTime instants before choosing a relative day' do
    date = rendered(DateTime.iso8601('2026-11-17T00:25:00Z'))
    expect(date.at_css('.date-display-label').text).to eq('Today')
    expect(date.at_css('.date-display-clock').text).to eq(' at 7:25 PM')
    expect(date['title']).to eq('Monday, November 16, 2026 at 7:25 PM EST')
  end

  it 'never shifts civil dates or invents a midnight timestamp' do
    date = rendered(Date.new(2026, 11, 17))
    expect(date.text).to eq('Tomorrow')
    expect(date['datetime']).to eq('2026-11-17')
    expect(date['title']).to eq('Tuesday, November 17, 2026')
    expect(date.at_css('.date-display-clock')).to be_nil
  end

  it 'preserves timestamp details when a separate booking range supplies the visible clock' do
    date = rendered(Time.utc(2026, 11, 16, 23, 30), show_time: false)
    expect(date.text).to eq('Today')
    expect(date.at_css('.date-display-clock')).to be_nil
    expect(date['title']).to include('6:30 PM EST')
  end

  it 'distinguishes repeated daylight-saving times by their local time zone abbreviations' do
    early = rendered(Time.utc(2026, 11, 1, 5, 30))
    late = rendered(Time.utc(2026, 11, 1, 6, 30))
    expect(early.text).to eq(late.text)
    expect(early['title']).to include('1:30 AM EDT')
    expect(late['title']).to include('1:30 AM EST')
    expect(early['datetime']).not_to eq(late['datetime'])
  end

  it 'counts local calendar days through a 25-hour daylight-saving day' do
    travel_to Time.utc(2026, 11, 2, 5, 30)
    expect(rendered(Time.utc(2026, 11, 1, 4, 15)).at_css('.date-display-label').text).to eq('Yesterday')
  end

  it 'retains relative labels across year boundaries' do
    travel_to Time.utc(2027, 1, 1, 15)
    expect(rendered(Date.new(2026, 12, 31)).text).to eq('Yesterday')
    expect(rendered(Date.new(2026, 12, 30), format: :compact).text).to eq('Last Wed')
  end

  it 'keeps calendar day numbers with complete civil-date hover details' do
    date = rendered(Date.new(2026, 11, 16), format: :day)
    expect(date.text).to eq('16')
    expect(date['title']).to eq('Monday, November 16, 2026')
    expect(date['tabindex']).to be_nil
  end

  it 'renders month precision without manufacturing a first-of-month date' do
    current = rendered(Date.new(2026, 11, 1), format: :month)
    future = rendered(Date.new(2027, 1, 1), format: :month)
    expect(current.text).to eq('November')
    expect(current['title']).to eq('November 2026')
    expect(current['datetime']).to eq('2026-11')
    expect(future.text).to eq('January 2027')
    expect(future['datetime']).to eq('2027-01')
  end
end
