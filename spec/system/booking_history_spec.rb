# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Booking history details', :aggregate_failures, :database, type: :system do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 16, 15)) { example.run } }

  let(:admin) { create_user(roles: ['system_admin']) }
  let(:participant) { create_user(name: 'History Model') }
  let(:program) { create_program(name: 'History Studio') }
  let(:booking) do
    track_booking(Booking.create!(program: program, user: participant, date: Date.new(2026, 12, 7),
                                  time_zone: 'UTC', starts_at: Time.utc(2026, 12, 7, 19),
                                  ends_at: Time.utc(2026, 12, 7, 21), status: 'canceled',
                                  reason: 'Travel plans changed.', gender_override_reason: 'Private manager override.',
                                  time_changes: [{ 'from' => Time.utc(2026, 12, 7, 18),
                                                   'to' => Time.utc(2026, 12, 7, 19),
                                                   'reason' => 'Later studio access.' }],
                                  attendance_changes: [{ 'confirmed' => true, 'changed_at' => Time.current,
                                                         'reason' => 'Attendance changed.' }]))
  end

  before do
    grant_participant_access(program, participant)
    booking
  end

  def expand_booking(viewport, name:)
    selector = "#booking-details-#{booking.id}"
    expect(page).to have_no_css(selector)
    toggle = find("summary[aria-controls='booking-details-#{booking.id}']")
    toggle_booking_details(toggle, selector) do
      expect_booking_explanations(selector)
      expect_confirmation_font(selector)
      expect_no_horizontal_overflow
      capture_screenshot("#{name}-#{viewport}")
    end
  end

  def expect_booking_explanations(selector)
    within(selector) do
      expect(page).to have_text('Travel plans changed.')
      expect(page).to have_text('Later studio access.')
      expect(page).to have_text('Confirmed on')
      expect(page).to have_text('Attendance changed.')
    end
  end

  def expect_confirmation_font(selector)
    paragraph = find("#{selector} p", text: 'Confirmed on')
    clock = paragraph.find('.date-display-clock')
    expect(clock.style('font-family', 'font-size')).to eq(paragraph.style('font-family', 'font-size'))
  end

  def toggle_booking_details(toggle, selector)
    cell = toggle.find(:xpath, 'ancestor::td')
    border = cell.style('border-bottom-color')
    toggle.click
    yield
    expect(cell.style('border-bottom-color')).not_to eq(border)
    toggle.send_keys(:enter)
    expect(page).to have_no_css(selector)
  end

  it 'opens account history explanations with the existing arrow treatment at every viewport' do
    sign_in_through_browser(admin)
    each_viewport do |viewport|
      visit history_admin_user_path(participant)
      expand_booking(viewport, name: 'account-booking-details')
      expect(page).to have_no_text(:all, 'Private manager override.')
    end
  end

  it 'moves program explanations and manager editing details under their arrows' do
    upcoming = track_booking(Booking.create!(program: program, user: participant, date: Date.new(2026, 12, 14),
                                             time_zone: 'UTC', starts_at: Time.utc(2026, 12, 14, 19),
                                             ends_at: Time.utc(2026, 12, 14, 21)))
    sign_in_through_browser(admin)
    each_viewport do |viewport|
      visit program_path(program, section: 'history')
      expand_booking(viewport, name: 'program-booking-details')
      find("summary[aria-controls='booking-details-#{upcoming.id}']").click
      expect(page).to have_link('Edit', href: edit_program_organizer_booking_path(program, upcoming))
      find("summary[aria-controls='booking-details-#{booking.id}']").click
      expect(page).to have_text('Gender-rule override: Private manager override.')
    end
  end

  it 'retains owner explanations without manager details and works without JavaScript' do
    sign_in_through_browser(participant)
    resize_to(:narrow)
    without_javascript do
      [history_profile_path, program_path(program, section: 'history')].each do |path|
        visit path
        expand_booking(:narrow, name: 'owner-booking-details')
        expect(page).to have_no_text(:all, 'Private manager override.')
        expect(page).to have_no_css('.booking-history a', text: 'Edit', visible: :all)
      end
    end
  end

  it 'omits empty disclosures instead of showing an arrow with no explanation' do
    other = track_booking(Booking.create!(program: program, user: participant, date: Date.new(2026, 12, 14),
                                          time_zone: 'UTC', ends_at: Time.utc(2026, 12, 14, 21)))
    sign_in_through_browser(participant)
    visit history_profile_path
    expect(page).to have_css("tr[data-booking='#{booking.id}'] summary")
    expect(page).to have_no_css("tr[data-booking='#{other.id}'] summary")
    expect(page).to have_no_css("#booking-details-#{other.id}", visible: :all)
  end
end
