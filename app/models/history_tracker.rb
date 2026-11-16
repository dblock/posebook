# frozen_string_literal: true

class HistoryTracker
  include Mongoid::History::Tracker

  index({ created_at: -1, _id: -1 })
end
