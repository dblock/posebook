# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountSettings, :aggregate_failures, :database do
  def email_token(user)
    token = SecureRandom.urlsafe_base64(32)
    user.update!(pending_email: 'confirmed@example.test', email_change_digest: Digest::SHA256.hexdigest(token),
                 email_change_expires_at: 30.minutes.from_now)
    token
  end

  it 'allows only one concurrent email confirmation' do
    user = create_user
    token = email_token(user)
    results = 2.times.map do
      Thread.new { User.find(user.id).confirm_email_change(token).present? }
    end.map(&:value)
    expect(results.count(true)).to eq(1)
  end

  it 'rejects a confirmation that expires after its page loads' do
    user = create_user
    token = email_token(user)
    stale = User.find(user.id)
    user.set(email_change_expires_at: 1.minute.ago)
    expect(stale.confirm_email_change(token)).to be_nil
  end

  it 'protects an account promoted to system admin after loading it for deactivation' do
    user = create_user
    User.find(user.id).set(roles: ['system_admin'])
    expect(user.deactivate).to be_nil
    expect(user.reload).to be_active
  end

  it 'rejects stale authenticated password changes after credentials have changed' do
    user = create_user
    stale = User.find(user.id)
    attributes = { current_password: DatabaseHelpers::TEST_PASSWORD, password: 'a fresh password for this test',
                   password_confirmation: 'a fresh password for this test' }
    user.change_password(attributes.dup)
    expect(stale.change_password(attributes.dup)).to be_nil
  end
end
