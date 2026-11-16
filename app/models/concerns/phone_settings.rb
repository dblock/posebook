# frozen_string_literal: true

module PhoneSettings
  extend ActiveSupport::Concern

  included do
    field :phone, type: String
    before_validation :normalize_phone
    validates :phone, presence: true
    validates :phone, format: { with: /\A\+[1-9]\d{7,14}\z/ }, allow_blank: true
  end

  def display_phone
    match = phone.to_s.match(/\A\+1(\d{3})(\d{3})(\d{4})\z/)
    match ? "+1 (#{match[1]}) #{match[2]}-#{match[3]}" : phone
  end

  private

  def normalize_phone
    self.phone = phone.to_s.strip.presence
    return if phone.blank? || !phone.match?(/\A\+?[0-9\s().-]+\z/)

    if phone.include?('(0)')
      errors.add(:phone,
                 'cannot include (0); omit an optional trunk prefix or enter a significant zero without parentheses')
      return
    end
    digits = normalized_phone_digits
    self.phone = "+#{digits}" if digits
  end

  def normalized_phone_digits
    digits = phone.gsub(/\D/, '')
    return digits if phone.start_with?('+')
    return digits.delete_prefix('00') if digits.start_with?('00')
    return digits unless digits.length == 10
    return unless digits.match?(/\A[2-9]/)

    "1#{digits}"
  end
end
