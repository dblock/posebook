# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Scoped notification settings', :aggregate_failures, :database, type: :request do
  let(:admin) { create_user(roles: ['system_admin']) }
  let(:program) { create_program }
  let(:defaults) { track_record(NotificationDefaults.create!(id: NotificationDefaults::ID)) }

  it 'creates audited admin defaults only when the first configuration is saved' do
    sign_in(admin)
    get admin_settings_notifications_path
    expect(NotificationDefaults.where(id: NotificationDefaults::ID)).not_to exist
    patch admin_settings_notification_path('password_reset'),
          params: { notification: { subject: 'Reset your account' } }
    saved = track_record(NotificationDefaults.where(id: NotificationDefaults::ID).first)
    expect(response).to redirect_to(edit_admin_settings_notification_path('password_reset'))
    expect(saved.notification_settings['password_reset']['subject']).to eq('Reset your account')
    expect(HistoryTracker.where('association_chain.id': saved.id, modifier_id: admin.id)).to exist
  end

  it 'lets only admins edit system templates while preserving required security links' do
    defaults
    sign_in(admin)
    get admin_settings_notifications_path
    expect(response.body).to include('Password Reset', 'Venue Coordinator Invitation', 'Application Rejected')
    patch admin_settings_notification_path('password_reset'),
          params: { notification: { subject: 'Reset your account', body: 'Missing link', enabled: '0' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('must include {reset_url}', 'cannot be disabled')
    expect(defaults.reload.notification_settings).to be_empty
    sign_in(create_user)
    get admin_settings_notifications_path
    expect(response).to have_http_status(:forbidden)
  end

  it 'saves admin defaults and renders safe unsaved system previews without sending mail' do
    defaults
    sign_in(admin)
    patch admin_settings_notification_path('password_reset'),
          params: { notification: { subject: 'Security for {recipient_name}', body: 'Reset: {reset_url}' } }
    expect(response).to redirect_to(edit_admin_settings_notification_path('password_reset'))
    post preview_admin_settings_notification_path('password_reset'),
         params: { notification: { subject: 'Preview for {recipient_name}',
                                   body: '<script>bad</script> {reset_url}' } },
         headers: { 'X-Notification-Preview' => 'true' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.css('script')).to be_empty
    expect(response.body).to include('Preview for Alex Example')
    expect(defaults.reload.notification_settings['password_reset']['subject']).to eq('Security for {recipient_name}')
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'limits venue defaults to venue managers and program defaults to program managers' do
    coordinator = create_user
    grant_coordinator_access(program, coordinator)
    sign_in(coordinator)
    get venue_notifications_path(program.venue)
    expect(response).to have_http_status(:not_found)
    get edit_program_notification_path(program, 'password_reset')
    expect(response).to have_http_status(:not_found)
    get edit_program_notification_path(program, 'venue_coordinator_invitation')
    expect(response).to have_http_status(:not_found)
    grant_venue_access(program.venue, coordinator)
    get venue_notifications_path(program.venue)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Venue Coordinator Invitation')
  end

  it 'saves venue defaults, inherits them in program editors and resets a program override' do
    sign_in(admin)
    patch venue_notification_path(program.venue, 'booking_invitation'),
          params: { notification: { subject: 'Venue invitation' } }
    expect(response).to redirect_to(edit_venue_notification_path(program.venue, 'booking_invitation'))
    get edit_program_notification_path(program, 'booking_invitation')
    expect(response.parsed_body.at_css('[name="notification[subject]"]')['value']).to eq('Venue invitation')
    patch program_notification_path(program, 'booking_invitation'),
          params: { notification: { subject: 'Local invitation' } }
    patch program_notification_path(program, 'booking_invitation'),
          params: { inherit: '1', notification: { subject: 'Discarded' } }
    expect(NotificationSetting.for(program.reload, 'booking_invitation').template('subject')).to eq('Venue invitation')
    expect(program.notification_settings['booking_invitation']).to be_empty
  end

  it 'lets people update only their own optional preferences without editing account roles' do
    user = create_user
    sign_in(user)
    get notifications_profile_path
    expect(response).to have_http_status(:ok)
    patch notifications_profile_path,
          params: { user: { booking_reminders_enabled: '0', application_reminders_enabled: '0',
                            coordinator_notifications_enabled: '0', roles: ['system_admin'] }, id: admin.id }
    expect(response).to redirect_to(notifications_profile_path)
    expect(user.reload).to have_attributes(booking_reminders_enabled: false, application_reminders_enabled: false,
                                           coordinator_notifications_enabled: false, roles: [])
    expect(admin.reload.coordinator_notifications_enabled?).to be(true)
  end

  it 'previews venue session-end timing without saving and inherits it after an explicit save' do
    sign_in(admin)
    post preview_venue_notification_path(program.venue, 'session_reminder'),
         params: { notification: { timing: 'previous_session_end' } },
         headers: { 'X-Notification-Preview' => 'true' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css('[data-preview-timing]').text).to include('9:00 PM')
    expect(program.venue.reload.notification_settings).to be_empty
    patch venue_notification_path(program.venue, 'session_reminder'),
          params: { notification: { timing: 'previous_session_end' } }
    expect(response).to redirect_to(edit_venue_notification_path(program.venue, 'session_reminder'))
    get edit_program_notification_path(program, 'session_reminder')
    expect(response.parsed_body.at_css('[name="notification[timing]"] option[selected]')['value'])
      .to eq('previous_session_end')
    expect(program.reload.notification_settings).to be_empty
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'renders the editor and synthetic preview for every listed admin and venue notification' do
    sign_in(admin)
    [admin_settings_notifications_path, venue_notifications_path(program.venue)].each do |list|
      get list
      paths = response.parsed_body.css('.notification-settings tbody a').pluck('href')
      paths.each do |path|
        get path
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.at_css('[data-preview-subject]')).to be_present
      end
    end
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
