# frozen_string_literal: true

class NotificationSettingsUpdate
  def initialize(scope:, user:)
    @scope = scope
    @user = user
  end

  def call(settings)
    attributes = { notification_settings: settings }
    return ProgramSettingsUpdate.new(program: @scope, user: @user).call(attributes) if @scope.is_a?(Program)
    return VenueSettingsUpdate.new(venue: @scope, user: @user).call(attributes) if @scope.is_a?(Venue)

    update_defaults(settings)
  end

  private

  def update_defaults(settings)
    NotificationDefaults.with_session do |session|
      session.with_transaction do
        persist_defaults(settings)
      end
    end
    @scope
  rescue Mongo::Error::OperationFailure => e
    raise unless e.code == 11_000 && !@retried

    @retried = true
    retry
  rescue Mongoid::Errors::Validations => e
    e.document
  end

  def authorize_defaults!
    raise LocationActivation::Forbidden unless @user.reload.active? && @user.system_admin?
  end

  def persist_defaults(settings)
    authorize_defaults!
    @scope = NotificationDefaults.current
    @scope.save! if @scope.new_record?
    @scope.inc(revision: 1)
    @scope.reload
    @scope.update!(notification_settings: @scope.notification_settings.merge(settings))
  end
end
