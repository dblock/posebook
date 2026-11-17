# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Compact date displays', :aggregate_failures, :database, type: :system do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 16, 15, 15)) { example.run } }

  let(:coordinator) { create_user(name: 'Studio Coordinator') }
  let(:program) do
    create_program(name: 'Figure Drawing Mondays', time_zone: 'America/New_York', start_time: '18:30',
                   end_time: '21:00', applications_enabled: true)
  end

  def prepare_history
    grant_venue_access(program.venue, coordinator)
    grant_coordinator_access(program, coordinator)
    applicant = create_user(name: 'Studio Model', email_verified_at: Time.current)
    application = track_record(ParticipantApplicationWorkflow.new(program: program, user: applicant)
                                                            .submit(message: nil, consent: '1'))
    sign_in_through_browser(coordinator)
    application
  end

  def expect_precise_date
    date = find('main time', match: :first)
    expect(date).to have_css('.date-display-label', text: 'Today', exact_text: true)
    expect(date).to have_css('.date-display-clock', text: '10:15 AM')
    expect(date[:title]).to eq('Monday, November 16, 2026 at 10:15 AM EST')
    expect(date[:'aria-label']).to eq(date[:title])
    date
  end

  def expect_single_line_date(date)
    label = date.find('.date-display-label')
    clock = date.find('.date-display-clock')
    expect((top_of(clock) - top_of(label)).abs).to be <= 4
    expect(width_of(date.find(:xpath, '..'))).to be >= 160
  end

  # rubocop:disable-next Spellcheck/Spelling -- Standard JavaScript DOM identifiers.
  def expect_plain_date(date)
    expect(date[:tabindex]).to be_nil
    expect(date.style('cursor')).to eq(date.find(:xpath, '..').style('cursor'))
    date.click
    expect(date.evaluate_script('getComputedStyle(this, "::after").content')).to eq('none')
  end

  it 'keeps application and history dates on one line without click expansion at every viewport' do
    prepare_history
    each_viewport do |viewport|
      [program_applications_path(program), history_program_applications_path(program)].each_with_index do |path, index|
        visit path
        date = expect_precise_date
        expect_plain_date(date)
        expect_single_line_date(date)
        expect_no_horizontal_overflow
        capture_screenshot("compact-date-table-#{index}-#{viewport}")
      end
    end
  end

  it 'fits longer dates from another year inside the table scrolling region' do
    prepare_history
    travel_to(Time.utc(2027, 11, 16, 15, 15))
    sign_in_through_browser(coordinator)
    each_viewport do
      [program_applications_path(program), history_program_applications_path(program)].each do |path|
        visit path
        date = find('tbody time', match: :first)
        expect(date).to have_text('Nov 16, 2026 at 10:15 AM')
        expect_single_line_date(date)
        expect_no_horizontal_overflow
      end
    end
  end

  it 'shows submission dates on application and invitation details without narrow page overflow' do
    application = prepare_history
    invitation = create_participant_invitation(program, coordinator)
    paths = [program_application_path(program, application), program_participant_invitation_path(program, invitation)]
    each_viewport do |viewport|
      paths.each_with_index do |path, index|
        visit path
        expect(page).to have_text('Submitted On:')
        expect_precise_date
        expect_no_horizontal_overflow
        capture_screenshot("compact-submission-#{index}-#{viewport}")
      end
    end
  end

  it 'keeps administrator account creation and update dates readable at every viewport' do
    user = create_user(created_at: Time.utc(2025, 12, 16, 15, 25), updated_at: Time.utc(2026, 11, 16, 16, 45))
    sign_in_through_browser(create_user(roles: ['system_admin']))
    each_viewport do |viewport|
      visit admin_user_path(user)
      within('.account-details') do
        expect(page).to have_text('Account Created')
        expect(page).to have_text('Account Updated')
        expect(all('time').pluck(:title)).to eq(['Tuesday, December 16, 2025 at 3:25 PM UTC',
                                                 'Monday, November 16, 2026 at 4:45 PM UTC'])
      end
      expect_no_horizontal_overflow
      capture_screenshot("compact-account-dates-#{viewport}")
    end
  end

  it 'keeps public session ranges and full hover timestamps without repeating the clock' do
    program
    each_viewport do |viewport|
      visit program_path(program)
      within('.next-session') do
        date = find('time')
        expect(date).to have_text('Today', exact: true)
        expect(date[:title]).to include('Monday, November 16, 2026', '6:30 PM EST')
        expect(date).to have_no_css('.date-display-clock')
        expect(page).to have_text('6:30 PM - 9:00 PM (2 hours 30 min)')
      end
      expect_no_horizontal_overflow
      capture_screenshot("compact-next-session-#{viewport}")
    end
  end

  it 'keeps hover details, ordinary date text, and calendar links working without JavaScript' do
    prepare_history
    without_javascript do
      visit history_program_applications_path(program)
      expect_plain_date(expect_precise_date)
      visit program_path(program, section: 'calendar')
      date = find(".calendar [data-date='2026-11-17'] time")
      expect(date.text).to eq('17')
      expect(date[:title]).to eq('Tuesday, November 17, 2026')
      within(".calendar [data-date='2026-11-17']") { click_on '17' }
      expect(page).to have_field('Date', with: '2026-11-17')
    end
  end
end
