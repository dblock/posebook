# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CursorPage, :aggregate_failures, :database do
  let(:program) { create_program }
  let(:admin) { create_user(roles: ['system_admin']) }
  let(:invitations) do
    Array.new(7) do
      create_participant_invitation(program, admin, created_at: Time.utc(2026, 11, 14) + Rational(1, 1000))
    end
  end

  %i[asc desc].each do |direction|
    context "with #{direction} ordering" do
      let(:scope) { program.participant_invitations.order_by(created_at: direction) }
      let(:ordered) { direction == :asc ? invitations : invitations.reverse }

      def page_at(cursor = nil)
        described_class.new(scope, cursor: cursor, per_page: 2)
      end

      it 'navigates tied values in both directions and stops at the actual boundaries' do
        expected = ordered
        first = page_at
        second = page_at(first.next_cursor)
        third = page_at(second.next_cursor)
        last = page_at(third.next_cursor)
        expect([first, second, third, last].flat_map(&:records)).to eq(expected)
        expect(first.previous_cursor).to be_nil
        expect(last.next_cursor).to be_nil
        back = page_at(last.previous_cursor)
        expect(back.records).to eq(third.records)
        expect(page_at(back.next_cursor).records).to eq(last.records)
        back = page_at(back.previous_cursor)
        expect(back.records).to eq(second.records)
        back = page_at(back.previous_cursor)
        expect(back.records).to eq(first.records)
        expect(back.previous_cursor).to be_nil
      end

      it 'resumes after removed anchors without duplicating or skipping surviving records' do
        expected = ordered
        first = page_at
        cursor = first.next_cursor
        first.records.each(&:destroy!)
        create_participant_invitation(program, admin,
                                      created_at: Time.utc(2026, 11, direction == :asc ? 13 : 15))
        second = page_at(cursor)
        expect(second.records).to eq(expected[2, 2])
        expect(page_at(second.next_cursor).records).to eq(expected[4, 2])
      end
    end
  end

  it 'ignores malformed, tampered, differently sorted, and foreign-scope cursors' do
    invitations
    scope = program.participant_invitations.order_by(created_at: :desc)
    first = described_class.new(scope, per_page: 2)
    foreign = create_participant_invitation(create_program, admin)
    foreign_cursor = described_class.new(foreign.program.participant_invitations.order_by(created_at: :desc),
                                         per_page: 1)
    create_participant_invitation(foreign.program, admin)
    tokens = ['invalid', "#{first.next_cursor}x", foreign_cursor.next_cursor,
              described_class.new(scope.reorder(created_at: :asc), per_page: 2).next_cursor,
              { unexpected: 'value' }]
    tokens.each do |token|
      page = described_class.new(scope, cursor: token, per_page: 2)
      expect(page.records).to eq(first.records)
      expect(page.cursor).to be_nil
    end
  end

  it 'keeps empty cursor ranges navigable back to the first results' do
    invitations
    scope = program.participant_invitations.order_by(created_at: :desc)
    first = described_class.new(scope, per_page: 6)
    cursor = first.next_cursor
    invitations.first.destroy!
    page = described_class.new(scope, cursor: cursor, per_page: 6)
    expect(page.records).to be_empty
    expect(page.cursor).to eq(cursor)
    expect(page.next_cursor).to be_nil
    expect(page.previous_cursor).to be_nil
  end
end
