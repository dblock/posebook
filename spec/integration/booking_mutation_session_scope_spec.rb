# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BookingMutation, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  it 'allows one upcoming booking per session, including the same date at the same venue' do
    venue = create_venue
    programs = Array.new(2) { create_program(venue: venue) }
    participant = create_user
    bookings = programs.map do |program|
      grant_participant_access(program, participant)
      track_booking(described_class.new(program: program, user: participant).book(date: '2026-11-16'))
    end
    expect(bookings.map(&:program_id)).to match_array(programs.map(&:id))
    expect(BookingClaim.where(user_id: participant.id).count).to eq(2)
    expect { described_class.new(program: programs.first, user: participant).book(date: '2026-11-23') }
      .to raise_error(BookingMutation::Invalid)
  end

  it 'does not turn an invitation for one session into participant access at its siblings' do
    venue = create_venue
    first = create_program(venue: venue)
    sibling = create_program(venue: venue)
    participant = create_user
    grant_participant_access(first, participant)
    expect { described_class.new(program: sibling, user: participant).book(date: '2026-11-16') }
      .to raise_error(BookingMutation::Invalid)
    expect(sibling.memberships.participants).to be_empty
  end
end
