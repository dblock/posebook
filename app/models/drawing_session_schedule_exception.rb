# frozen_string_literal: true

class DrawingSessionScheduleException
  include Mongoid::Document
  include Mongoid::Timestamps
  include HistoryTracking

  belongs_to :drawing_session, inverse_of: :schedule_exceptions
  field :date, type: Date
  field :mode, type: String, default: 'open'
  field :start_time, type: String
  field :reason, type: String

  attr_readonly :drawing_session_id, :date
  index({ drawing_session_id: 1, date: 1 }, unique: true)
  track_history on: %i[drawing_session_id date mode start_time reason],
                modifier_field_optional: true, modifier_field_inverse_of: nil, track_blank_changes: true

  before_validation do
    self.reason = reason.to_s.strip
    self.start_time = mode == 'open' ? start_time.to_s.strip : nil
  end
  validates :date, :reason, presence: true
  validates :reason, length: { maximum: 200 }
  validates :mode, inclusion: { in: %w[open closed regular] }
  validates :start_time, format: { with: DrawingSessionSchedule::TIME_FORMAT }, if: -> { mode == 'open' }
  validate :validate_date
  validate :validate_local_time

  private

  def validate_date
    return unless date && drawing_session

    today = Time.current.in_time_zone(drawing_session.time_zone).to_date
    last_date = today.advance(months: drawing_session.booking_horizon_months)
    errors.add(:date, 'must be within the booking window') unless date.between?(today, last_date)
  end

  def validate_local_time
    return unless date && drawing_session

    clock = effective_start_time
    return unless clock&.match?(DrawingSessionSchedule::TIME_FORMAT)

    DrawingSessionSchedule.local_start(date, clock, drawing_session.time_zone)
  rescue ArgumentError => e
    errors.add(:start_time, e.message)
  end

  def effective_start_time
    return start_time if mode == 'open'
    if mode == 'regular' && drawing_session.available_weekdays.include?(date.wday.to_s)
      return drawing_session.start_time
    end

    nil
  end
end
