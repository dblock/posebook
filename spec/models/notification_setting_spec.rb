# frozen_string_literal: true

require 'rails_helper'

RSpec.describe NotificationSetting, :aggregate_failures, :database do
  let(:program) { create_program }
  let(:defaults) { track_record(NotificationDefaults.create!(id: NotificationDefaults::ID)) }

  it 'inherits each field through admin, venue, and program settings without freezing inherited text' do
    defaults.update!(notification_settings: { 'booking_invitation' => { 'subject' => 'Admin subject' } })
    program.venue.update!(notification_settings: { 'booking_invitation' => { 'body' => 'Venue {booking_url}' } })
    setting = described_class.for(program, 'booking_invitation')
    expect(setting.template('subject')).to eq('Admin subject')
    expect(setting.template('body')).to eq('Venue {booking_url}')
    setting.assign_attributes(subject: setting.template('subject'), body: setting.template('body'))
    expect(setting.stored_attributes).to be_empty
    program.update!(notification_settings: { 'booking_invitation' => { 'subject' => 'Local' } })
    setting = described_class.for(program, 'booking_invitation')
    setting.assign_attributes(subject: '')
    expect(setting.template('subject')).to eq('Admin subject')
    expect(setting.stored_attributes).to be_empty
  end

  it 'uses the inherited enable state and preserves an explicit local override' do
    defaults.update!(notification_settings: { 'session_reminder' => { 'enabled' => false } })
    expect(described_class.for(program, 'session_reminder').enabled).to be(false)
    program.update!(notification_settings: { 'session_reminder' => { 'enabled' => true } })
    expect(described_class.for(program, 'session_reminder').stored_attributes).to eq('enabled' => true)
  end

  it 'does not freeze inherited messages when browsers submit different line endings' do
    setting = described_class.for(program, 'booking_invitation')
    setting.body = setting.template('body').gsub("\n", "\r\n")
    expect(setting.stored_attributes).to be_empty
  end

  it 'does not let secret action links enter a subject or disappear from a security message' do
    setting = described_class.for(defaults, 'password_reset')
    setting.assign_attributes(subject: 'Reset {reset_url}', body: 'No action', enabled: false)
    expect(setting).not_to be_valid
    expect(setting.errors.full_messages.join).to include('cannot include action links', 'must include {reset_url}',
                                                         'cannot be disabled')
  end

  it 'keeps draft reminders before automatic expiry' do
    setting = described_class.for(program, 'application_draft')
    setting.days_after = 30
    expect(setting).not_to be_valid
    setting.days_after = 0
    expect(setting).to be_valid
  end

  it 'applies admin security content through the real delivery worker regardless of personal preferences' do
    defaults.update!(notification_settings: { 'password_reset' => { 'subject' => 'Security for {recipient_name}',
                                                                    'body' => 'Reset now: {reset_url}' } })
    user = create_user(booking_reminders_enabled: false, application_reminders_enabled: false,
                       coordinator_notifications_enabled: false)
    user.send_password_reset
    deliver_emails
    expect(ActionMailer::Base.deliveries.last.subject).to eq("Security for #{user.name}")
    expect(ActionMailer::Base.deliveries.last.body.decoded).to include('Reset now:', '/password_resets/')
  end

  it 'rechecks invitation configuration after enqueueing' do
    organizer = create_user
    grant_coordinator_access(program, organizer)
    invitation = create_participant_invitation(program, organizer, email: 'invited@example.test')
    EmailDelivery.enqueue('participant_invitation', invitation, token: invitation.token,
                                                                expires_at: invitation.expires_at)
    program.update!(notification_settings: { 'participant_invitation' => { 'enabled' => false } })
    deliver_emails
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'preserves other admin settings across competing updates' do
    defaults
    admin = create_user(roles: ['system_admin'])
    edits = { 'booking_invitation' => { 'subject' => 'Global invitation' },
              'session_reminder' => { 'enabled' => false } }
    edits.map do |kind, fields|
      Thread.new do
        NotificationSettingsUpdate.new(scope: defaults, user: User.find(admin.id)).call(kind => fields)
      end
    end.each(&:value)
    expect(defaults.reload.notification_settings).to eq(edits)
  end
end
