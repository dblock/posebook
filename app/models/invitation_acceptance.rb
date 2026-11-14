# frozen_string_literal: true

class InvitationAcceptance
  class Unavailable < StandardError; end

  attr_reader :user

  def initialize(token:, user: nil, attributes: {})
    @token = token
    @existing_user = user
    @attributes = attributes.slice(:name, :email, :phone, :gender, :password, :password_confirmation,
                                   *PublicProfile::FIELDS)
  end

  def call
    ModelInvitation.with_session do |session|
      session.with_transaction { accept(session) }
    end
    user
  end

  private

  def accept(session)
    invitation = ModelInvitation.available(@token)
    raise Unavailable unless invitation

    @user = @existing_user || User.new(@attributes)
    raise Unavailable unless user.active?

    user.save! if user.new_record?
    claim(invitation, session)
    VenueMembership.grant_model_access(invitation.venue, user, session: session)
  end

  def claim(invitation, session)
    changed = ModelInvitation.collection.find(
      _id: invitation.id, used_at: nil, revoked_at: nil, expires_at: { '$gt' => Time.current }
    ).find_one_and_update(
      { '$set' => { used_at: Time.current, used_by_id: user.id, updated_at: Time.current } }, session: session
    )
    raise Unavailable unless changed
  end
end
