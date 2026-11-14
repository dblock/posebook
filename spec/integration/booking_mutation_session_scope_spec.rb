# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BookingMutation, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 11, 13, 15)) { example.run } }

  it 'allows one upcoming booking per session, including the same date at the same venue' do
    venue = create_venue
    programs = Array.new(2) { create_drawing_session(venue: venue) }
    model = create_user
    bookings = programs.map do |program|
      grant_model_access(program, model)
      track_booking(described_class.new(drawing_session: program, user: model).book(date: '2026-11-16'))
    end
    expect(bookings.map(&:drawing_session_id)).to match_array(programs.map(&:id))
    expect(ModelBookingClaim.where(user_id: model.id).count).to eq(2)
    expect { described_class.new(drawing_session: programs.first, user: model).book(date: '2026-11-23') }
      .to raise_error(BookingMutation::Invalid)
  end

  it 'does not turn an invitation for one session into model access at its siblings' do
    venue = create_venue
    first = create_drawing_session(venue: venue)
    sibling = create_drawing_session(venue: venue)
    model = create_user
    grant_model_access(first, model)
    expect { described_class.new(drawing_session: sibling, user: model).book(date: '2026-11-16') }
      .to raise_error(BookingMutation::Invalid)
    expect(sibling.memberships.models).to be_empty
  end
end
