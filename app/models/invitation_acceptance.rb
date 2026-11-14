# frozen_string_literal: true

class InvitationAcceptance
  class Unavailable < StandardError; end
  class RecipientMismatch < StandardError; end

  attr_reader :user

  def initialize(token:, user: nil, attributes: {}, invitation_class: ParticipantInvitation)
    @token = token
    @existing_user = user
    @invitation_class = invitation_class
    @attributes = attributes.slice(:name, :email, :phone, :gender, :password, :password_confirmation,
                                   *PublicProfile::FIELDS)
  end

  def call
    @invitation_class.with_session do |session|
      session.with_transaction { accept(session) }
    end
    user
  end

  private

  def accept(session)
    invitation = @invitation_class.available(@token)
    raise Unavailable unless invitation

    prepare_user(invitation)
    user.save! if user.new_record?
    claim(invitation, session)
    invitation.grant_access(user, session: session)
  end

  def prepare_user(invitation)
    @user = @existing_user ? User.find(@existing_user.id) : User.new(@attributes)
    raise Unavailable unless user.active?
    raise RecipientMismatch unless invitation.acceptable_by?(user)
  end

  def claim(invitation, session)
    changed = @invitation_class.collection.find(
      _id: invitation.id, used_at: nil, revoked_at: nil, expires_at: { '$gt' => Time.current }
    ).find_one_and_update(
      { '$set' => { used_at: Time.current, used_by_id: user.id, updated_at: Time.current } }, session: session
    )
    raise Unavailable unless changed
  end
end
