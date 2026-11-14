# frozen_string_literal: true

class ModelBookingClaim
  include Mongoid::Document

  belongs_to :venue, inverse_of: nil
  belongs_to :user, inverse_of: nil
  belongs_to :model_booking, inverse_of: nil
  field :date, type: Date
  field :ends_at, type: Time

  index({ venue_id: 1, date: 1 }, unique: true)
  index({ venue_id: 1, user_id: 1 }, unique: true)
  validates :date, :ends_at, presence: true
end
