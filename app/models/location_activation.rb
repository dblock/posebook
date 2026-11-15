# frozen_string_literal: true

class LocationActivation
  class Forbidden < StandardError; end
  class Invalid < StandardError; end

  def initialize(location:, user:)
    @location = location
    @user = user
  end

  def call(value)
    raise Invalid unless [true, false, 'true', 'false'].include?(value)

    @location.class.with_session do |session|
      session.with_transaction do
        save_activation(value.to_s == 'true')
      end
    end
    @location
  end

  private

  def save_activation(active)
    @location = @location.class.find(@location.id)
    raise Forbidden unless @user.reload.active? && authorized?

    updates = { active: active }
    updates[:schedule_revision] = @location.schedule_revision + 1 if @location.is_a?(Program)
    @location.assign_attributes(updates)
    # Access changes must not be blocked by unrelated legacy settings.
    @location.save!(validate: false)
  end

  def authorized?
    @location.is_a?(Venue) ? @user.system_admin? : @location.venue.coordinated_by?(@user)
  end
end
