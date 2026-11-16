# frozen_string_literal: true

# Dated sessions of publicly viewable programs over the next two weeks, with their confirmed bookings.
class UpcomingSessions
  include Enumerable

  Session = Data.define(:program, :calendar, :date, :starts_at, :booking)
  DAYS = 14

  def initialize(programs = Program.viewable_by(nil), days: DAYS)
    @programs = programs.includes(:venue).to_a
    @days = days
  end

  def each(&)
    sessions.each(&)
  end

  private

  def sessions
    @sessions ||= @programs.flat_map { |program| sessions_for(program) }
                           .sort_by { |session| [session.starts_at, session.program.name] }
  end

  def sessions_for(program)
    calendar = ProgramCalendar.new(program)
    (calendar.today..[calendar.today + @days, calendar.last_date].min).filter_map do |date|
      next unless calendar.session_on?(date) && calendar.starts_at(date) > Time.current

      Session.new(program: program, calendar: calendar, date: date, starts_at: calendar.starts_at(date),
                  booking: bookings[[program.id, date]])
    end
  end

  def bookings
    @bookings ||= Booking.where(:program_id.in => @programs.map(&:id), status: 'confirmed',
                                :date.gte => Date.current - 1, :date.lte => Date.current + @days + 1)
                         .includes(:user).index_by { |booking| [booking.program_id, booking.date] }
  end
end
