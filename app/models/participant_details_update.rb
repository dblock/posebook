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
    @membership.display_name_override = attributes[:display_name] if attributes.key?(:display_name)
    @membership.notes = attributes[:notes] if attributes.key?(:notes)
    @membership.instagram_hidden = attributes[:instagram_hidden] == '1' if attributes.key?(:instagram_hidden)
    @membership.photos_hidden = attributes[:photos_hidden] == '1' if attributes.key?(:photos_hidden)
    @membership.save! if @membership.valid?
  end
end
