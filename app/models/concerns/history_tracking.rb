# frozen_string_literal: true

module HistoryTracking
  extend ActiveSupport::Concern

  included do
    include Mongoid::History::Trackable

    before_save { self.modifier_id = Current.user&.id }
    before_destroy { self.modifier_id = Current.user&.id }
  end

  private

  def save_tracked_change(changes, validate: true)
    record = nil
    self.class.with_session do |session|
      session.with_transaction do
        record = yield.first
        next unless record

        record.assign_attributes(changes)
        next if record.save(validate: validate)

        errors.copy!(record.errors)
        record = nil
      end
    end
    record
  end
end
