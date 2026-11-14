# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, :aggregate_failures, :database do
  it 'normalizes email and hashes passwords without granting roles by default' do
    user = create_user(email: ' Participant@Example.test ')

    expect(user.email).to eq('participant@example.test')
    expect(user.password_digest).not_to eq(DatabaseHelpers::TEST_PASSWORD)
    expect(user.authenticate(DatabaseHelpers::TEST_PASSWORD)).to eq(user)
    expect(user).not_to be_system_admin
  end

  it 'rejects invalid email, missing name, short passwords, and unknown roles' do
    user = described_class.new(user_attributes(name: '', email: 'invalid', password: 'short',
                                               password_confirmation: 'short', roles: ['unknown']))

    expect(user).not_to be_valid
    expect(user.errors.attribute_names).to include(:name, :email, :password, :roles)
  end

  it 'rejects a password confirmation mismatch and duplicate normalized email' do
    original = create_user
    user = described_class.new(user_attributes(email: original.email.upcase, password_confirmation: 'different'))

    expect(user).not_to be_valid
    expect(user.errors.attribute_names).to include(:email, :password_confirmation)
  end

  it 'rejects passwords longer than the bcrypt byte limit' do
    user = described_class.new(user_attributes(password: 'x' * 73, password_confirmation: 'x' * 73))

    expect(user).not_to be_valid
    expect(user.errors[:password]).not_to be_empty
  end

  it 'allows only one first-user claim when registration checks race' do
    allow(described_class).to receive(:exists?).and_return(false)
    results = 2.times.map do
      Thread.new { described_class.bootstrap(user_attributes) }
    end.map(&:value)
    results.select(&:persisted?).each { |user| track_record(user) }

    expect(results.count(&:persisted?)).to eq(1)
    expect(results.find(&:persisted?)).to be_system_admin
    expect(results.reject(&:persisted?).first.errors[:base]).to include('Registration is closed.')
  end

  it 'refuses a bootstrap claim after any user exists' do
    create_user
    user = described_class.bootstrap(user_attributes)

    expect(user).not_to be_persisted
    expect(user.errors[:base]).to include('Registration is closed.')
  end

  it 'invalidates previous reset links when a newer link is requested' do
    user = create_user
    old_token = reset_token(user)
    new_token = reset_token(user)

    expect(described_class.for_password_reset(old_token)).to be_nil
    expect(described_class.for_password_reset(new_token)).to eq(user)
    expect(user.reload.password_reset_digest).not_to eq(new_token)
  end

  it 'allows a reset token to win only one concurrent password update' do
    user = create_user
    token = reset_token(user)
    copies = 2.times.map { described_class.for_password_reset(token) }
    results = copies.map do |copy|
      Thread.new do
        copy.reset_password(token, password: 'a new sufficiently long password',
                                   password_confirmation: 'a new sufficiently long password').present?
      end
    end.map(&:value)

    expect(results.count(true)).to eq(1)
    expect(user.reload.authenticate('a new sufficiently long password')).to eq(user)
  end

  it 'does not find empty or unknown reset tokens' do
    expect(described_class.for_password_reset('')).to be_nil
    expect(described_class.for_password_reset('unknown')).to be_nil
  end
end
