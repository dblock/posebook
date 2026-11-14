# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvitationAcceptance, :aggregate_failures, :database do
  it 'atomically accepts a personal invitation once and rolls back a competing account' do
    venue = create_venue
    invitation = create_model_invitation(venue, create_user(roles: ['system_admin']))
    attributes = Array.new(2) { user_attributes }
    results = attributes.map do |values|
      Thread.new do
        described_class.new(token: invitation.token, attributes: values).call
      rescue described_class::Unavailable
        nil
      end
    end.map(&:value)
    users = User.where(:email.in => attributes.pluck(:email)).to_a.each { |user| track_record(user) }
    users.each { |user| track_model_membership(venue, user) }
    expect(results.compact.size).to eq(1)
    expect(users.size).to eq(1)
    expect(invitation.reload.used_by_id).to eq(users.first.id)
    expect(venue.memberships.count).to eq(1)
  end
end
