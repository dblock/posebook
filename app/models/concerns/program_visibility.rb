# frozen_string_literal: true

module ProgramVisibility
  extend ActiveSupport::Concern

  class_methods do
    def visible_to(user)
      return all if user.system_admin?

      ids = ProgramMembership.where(user_id: user.id,
                                    :roles.in => %w[program_coordinator
                                                    participant]).distinct(:program_id)
      where('$or' => [{ :id.in => ids }, { :venue_id.in => Venue.coordinated_by(user).distinct(:id) }])
    end

    def managed_by(user)
      return all if user.system_admin?

      ids = ProgramMembership.coordinators.where(user_id: user.id).distinct(:program_id)
      where('$or' => [{ :id.in => ids }, { :venue_id.in => Venue.coordinated_by(user).distinct(:id) }])
    end

    def retained_for(user)
      ids = managed_by(user).distinct(:id) + Booking.upcoming.where(user_id: user.id).distinct(:program_id)
      where(:id.in => ids)
    end

    def viewable_by(user)
      return all if user&.system_admin?

      public_scope = { :active.ne => false, :venue_id.in => Venue.active.distinct(:id) }
      return where(public_scope) unless user

      any_of(public_scope, { :id.in => retained_for(user).distinct(:id) })
    end
  end

  def booking_active?
    active? && venue.active?
  end

  def viewable_by?(user)
    booking_active? || (user && self.class.retained_for(user).exists?(id: id))
  end

  def managed_by?(user)
    venue.coordinated_by?(user) || memberships.coordinators.exists?(user_id: user.id)
  end
end
