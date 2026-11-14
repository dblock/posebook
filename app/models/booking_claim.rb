# frozen_string_literal: true

class BookingClaim
  include Mongoid::Document

  belongs_to :program, inverse_of: nil
  belongs_to :user, inverse_of: nil
  belongs_to :booking, inverse_of: nil
  field :date, type: Date
  field :ends_at, type: Time

  index({ program_id: 1, date: 1 }, unique: true)
  index({ program_id: 1, user_id: 1 }, unique: true)
  validates :date, :ends_at, presence: true
end
