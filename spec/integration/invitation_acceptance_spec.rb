# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InvitationAcceptance, :aggregate_failures, :database do
  it 'atomically accepts a personal invitation once and rolls back a competing account' do
    program = create_program
    invitation = create_participant_invitation(program, create_user(roles: ['system_admin']))
    attributes = Array.new(2) { user_attributes }
    results = attributes.map do |values|
      Thread.new do
        described_class.new(token: invitation.token, attributes: values).call
      rescue described_class::Unavailable
        nil
      end
    end.map(&:value)
    users = User.where(:email.in => attributes.pluck(:email)).to_a.each { |user| track_record(user) }
    users.each { |user| track_participant_membership(program, user) }
    expect(results.compact.size).to eq(1)
    expect(users.size).to eq(1)
    expect(invitation.reload.used_by_id).to eq(users.first.id)
    expect(program.memberships.count).to eq(1)
    expect(HistoryTracker.where(:'modified.email'.in => attributes.pluck(:email)).count).to eq(1)
  end

  it 'rolls back coordinator registration and token consumption when granting the role fails' do
    venue = create_venue
    invitation = create_coordinator_invitation(venue, create_user(roles: ['system_admin']))
    attributes = user_attributes(email: invitation.email)
    allow(VenueMembership).to receive(:grant_coordinator_access).and_raise(IOError, 'Failed grant')
    expect do
      described_class.new(token: invitation.token, attributes: attributes,
                          invitation_class: CoordinatorInvitation).call
    end.to raise_error(IOError, 'Failed grant')
    expect(User.where(email: invitation.email)).to be_empty
    expect(CoordinatorInvitation.available(invitation.token)).to eq(invitation.reload)
    expect(invitation.used_at).to be_nil
  end

  it 'permits only one concurrent acceptance of a coordinator invitation' do
    venue = create_venue
    user = create_user
    invitation = create_coordinator_invitation(venue, create_user(roles: ['system_admin']), email: user.email)
    results = 2.times.map do
      Thread.new do
        described_class.new(token: invitation.token, user: user, invitation_class: CoordinatorInvitation).call
      rescue described_class::Unavailable
        nil
      end
    end.map(&:value)
    membership = track_record(VenueMembership.find_by(venue_id: venue.id, user_id: user.id))
    expect(results.compact).to eq([user])
    expect(membership.roles).to eq(['venue_coordinator'])
    expect(invitation.reload.used_by_id).to eq(user.id)
  end

  it 'rechecks the stored recipient email rather than accepting a stale account object' do
    user = create_user
    invitation = create_participant_invitation(create_program, create_user(roles: ['system_admin']), email: user.email)
    User.find(user.id).update!(email: 'changed@example.test')
    expect do
      described_class.new(token: invitation.token, user: user).call
    end.to raise_error(described_class::RecipientMismatch)
    expect(invitation.reload.used_at).to be_nil
    expect(invitation.program.memberships).to be_empty
  end
end
