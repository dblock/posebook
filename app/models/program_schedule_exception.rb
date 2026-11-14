# frozen_string_literal: true

class ProgramScheduleException
  include Mongoid::Document
  include Mongoid::Timestamps
  include HistoryTracking

  belongs_to :program, inverse_of: :schedule_exceptions
  field :date, type: Date
  field :mode, type: String, default: 'open'
  field :start_time, type: String
  field :end_time, type: String
  field :reason, type: String

  attr_readonly :program_id, :date
  index({ program_id: 1, date: 1 }, unique: true)
  track_history on: %i[program_id date mode start_time end_time reason],
                modifier_field_optional: true, modifier_field_inverse_of: nil, track_blank_changes: true

  before_validation do
    self.reason = reason.to_s.strip
    self.start_time = mode == 'open' ? start_time.to_s.strip : nil
    self.end_time = mode == 'open' ? end_time.to_s.strip.presence : nil
  end
  validates :date, :reason, presence: true
  validates :reason, length: { maximum: 200 }
  validates :mode, inclusion: { in: %w[open closed regular] }
  validates :start_time, format: { with: ProgramSchedule::TIME_FORMAT }, if: -> { mode == 'open' }
  validates :end_time, format: { with: ProgramSchedule::TIME_FORMAT }, allow_nil: true
  validate :validate_date
  validate :validate_local_time

  private

  def validate_date
    return unless date && program

    today = Time.current.in_time_zone(program.time_zone).to_date
    last_date = today.advance(months: program.booking_horizon_months)
    errors.add(:date, 'must be within the booking window') unless date.between?(today, last_date)
  end

  def validate_local_time
    return unless date && program

    clock = effective_start_time
    return unless clock&.match?(ProgramSchedule::TIME_FORMAT)

    ProgramSchedule.local_start(date, clock, program.time_zone)
    validate_local_end(clock)
  rescue ArgumentError => e
    errors.add(:start_time, e.message)
  end

  def validate_local_end(clock)
    ending = mode == 'open' ? end_time : program.end_time
    return unless ending&.match?(ProgramSchedule::TIME_FORMAT)

    ProgramSchedule.local_end(date, clock, ending, program.time_zone)
  rescue ArgumentError => e
    errors.add(:end_time, e.message)
  end

  def effective_start_time
    return start_time if mode == 'open'
    return program.start_time if mode == 'regular' && program.available_weekdays.include?(date.wday.to_s)

    nil
  end
end
