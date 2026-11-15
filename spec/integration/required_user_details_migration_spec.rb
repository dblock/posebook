# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RequiredUserDetailsMigration, :aggregate_failures, :database do
  it 'fills only missing fields, audits updates, and is safe to repeat for active and inactive users' do
    missing = create_user(active: false)
    phone_only = create_user(gender: 'female')
    gender_only = create_user(phone: '+12025550102')
    complete = create_user(phone: '+12025550103', gender: 'other')
    missing.set(phone: nil, gender: nil)
    phone_only.set(phone: '')
    gender_only.set(gender: nil)
    users = User.where(:id.in => [missing.id, phone_only.id, gender_only.id, complete.id])

    described_class.call(users)
    expect(missing.reload).to have_attributes(phone: '+12025550100', gender: 'male', active: false)
    expect(phone_only.reload).to have_attributes(phone: '+12025550100', gender: 'female')
    expect(gender_only.reload).to have_attributes(phone: '+12025550102', gender: 'male')
    expect(complete.reload).to have_attributes(phone: '+12025550103', gender: 'other')
    expect(missing.history_tracks.last.modified).to include('phone' => '+12025550100', 'gender' => 'male')
    counts = users.map { |user| user.history_tracks.count }
    described_class.call(users)
    expect(users.map { |user| user.history_tracks.count }).to eq(counts)
  end
end
