# frozen_string_literal: true

class RequiredUserDetailsMigration
  PLACEHOLDER_PHONE = '+12025550100'
  DEFAULT_GENDER = 'male'

  def self.call(users = User.all)
    users.each { |user| backfill(user.id) }
  end

  def self.backfill(id)
    User.with_session do |session|
      session.with_transaction do
        current = User.find(id)
        next if current.phone.present? && current.gender.present?

        current.phone = PLACEHOLDER_PHONE if current.phone.blank?
        current.gender = DEFAULT_GENDER if current.gender.blank?
        current.save!
      end
    end
  end
  private_class_method :backfill
end
