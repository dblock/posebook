# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Program notifications', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:program) { create_program(time_zone: 'America/New_York') }
  let(:organizer) { create_user }

  before do
    grant_coordinator_access(program, organizer)
    sign_in(organizer)
  end

  def update_notification(kind = 'confirmation_request', **attributes)
    patch program_notification_path(program, kind),
          params: { notification: attributes }
  end

  it 'lists notification purposes and saved states separately from the editor' do
    update_notification('session_reminder', enabled: '0')
    get program_notifications_path(program)
    expect(response).to have_http_status(:ok)
    document = response.parsed_body
    row = document.css('tbody tr').find { |entry| entry.text.include?('Upcoming Session Reminder') }
    expect(row.text).to include('Reminds participants of their upcoming session', 'Disabled')
    expect(row.at_css('a')['href']).to eq(edit_program_notification_path(program, 'session_reminder'))
    expect(document.css('[data-notification-editor], [data-notification-preview]')).to be_empty
  end

  it 'shows defaults and sample previews without sending mail or creating bookings' do
    get edit_program_notification_path(program, 'confirmation_request')
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('At Previous Session End', 'Email Preview', 'Alex Example')
    expect(response.parsed_body.at_css('[name="notification[time]"]')['value']).to eq('12:00')
    expect(program.bookings).to be_empty
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'saves timing and full templates and resets cleared fields independently' do
    update_notification(enabled: '1', timing: 'days_before', days_before: '8', time: '13:15',
                        subject: 'Hello {participant_name}', body: "Attend {program_name}:\n{confirmation_url}")
    expect(response).to redirect_to(edit_program_notification_path(program, 'confirmation_request'))
    setting = BookingNotificationSetting.for(program.reload, 'confirmation_request')
    expect(setting.days_before).to eq(8)
    expect(setting.time).to eq('13:15')
    expect(setting.template('subject')).to eq('Hello {participant_name}')
    update_notification(subject: '  ', body: '')
    setting = BookingNotificationSetting.for(program.reload, 'confirmation_request')
    expect(setting.subject).to be_nil
    expect(setting.body).to be_nil
    expect(setting.template('body')).to include('{confirmation_url}')
    expect(setting.time).to eq('13:15')
  end

  it 'renders unsaved content with escaping through the preview endpoint' do
    post preview_program_notification_path(program, 'confirmation_reminder'),
         params: { notification: { subject: 'For {participant_name}',
                                   body: '<script>alert(1)</script> {booking_url}' } },
         headers: { 'X-Notification-Preview' => 'true' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('For Alex Example')
    expect(response.parsed_body.css('script')).to be_empty
    expect(program.reload.notification_settings).to be_empty
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'rejects unknown placeholders, unsafe headers, and invalid timing without losing edits' do
    update_notification(subject: "Hello\nTo: other@example.test", body: 'Keep {unknown}', days_before: '-1',
                        time: '25:01')
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('unknown placeholders', 'single line', 'Keep {unknown}')
    expect(program.reload.notification_settings).to be_empty
  end

  it 'does not allow participant or unrelated coordinator access to settings or previews' do
    other = create_user
    grant_participant_access(program, other)
    sign_in(other)
    get program_notifications_path(program)
    expect(response).to have_http_status(:not_found)
    get edit_program_notification_path(program, 'confirmation_request')
    expect(response).to have_http_status(:not_found)
    update_notification(subject: 'Not allowed')
    expect(response).to have_http_status(:not_found)
    post preview_program_notification_path(program, 'confirmation_request'),
         params: { notification: { body: 'Not allowed' } }
    expect(response).to have_http_status(:not_found)
    expect(program.reload.notification_settings).to be_empty
  end

  it 'does not overwrite a different notification saved from another settings page' do
    update_notification('session_reminder', days_before: '2', time: '11:00')
    update_notification(subject: 'Request')
    expect(BookingNotificationSetting.for(program.reload, 'session_reminder').days_before).to eq(2)
    expect(BookingNotificationSetting.for(program, 'confirmation_request').subject).to eq('Request')
  end

  it 'rejects unknown notification types' do
    get edit_program_notification_path(program, 'password_reset')
    expect(response).to have_http_status(:not_found)
  end

  it 'previews a real scheduled date when the sample would fall in a daylight saving gap' do
    travel_to Time.utc(2027, 2, 28, 12) do
      sign_in(organizer)
      program.update!(available_weekdays: ['0'], start_time: '02:30')
      get edit_program_notification_path(program, 'confirmation_request')
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.at_css('[data-preview-subject]').text).to include('March 21')
    end
  end
end
