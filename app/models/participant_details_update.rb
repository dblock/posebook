# frozen_string_literal: true

class ParticipantDetailsUpdate
  def initialize(program:, user:)
    @program = program
    @user = user
  end

  def call(id, attributes)
    ProgramMembership.with_session do |session|
      session.with_transaction do
        @membership = find_membership(id)
        update_details(attributes)
      end
    end
    @membership
  end

  private

  def find_membership(id)
    actor = User.active.find(@user.id)
    program = Program.managed_by(actor).find(@program.id)
    program.memberships.participants.find(id)
  end

  def update_details(attributes)
    participant = @membership.user
    names = attributes.slice(:name, :display_name)
    participant.assign_attributes(names)
    @membership.notes = attributes[:notes] if attributes.key?(:notes)
    valid_names = names.empty? || participant.valid?
    return unless @membership.valid? && valid_names

    participant.save! unless names.empty?
    @membership.save!
  end
end
