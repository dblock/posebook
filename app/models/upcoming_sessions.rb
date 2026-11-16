# frozen_string_literal: true

# Dated sessions of publicly viewable programs over the next two weeks, with their confirmed bookings.
class UpcomingSessions
  include Enumerable

  Session = Data.define(:program, :calendar, :date, :starts_at, :booking, :membership)
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
    calendar = ProgramCalendar.new(program, exceptions: exceptions.fetch(program.id, []))
    (calendar.today..[calendar.today + @days, calendar.last_date].min).filter_map do |date|
      next unless calendar.session_on?(date) && calendar.starts_at(date) > Time.current

      session_for(program, calendar, date)
    end
  end

  def session_for(program, calendar, date)
    booking = bookings[[program.id, date]]
    Session.new(program: program, calendar: calendar, date: date, starts_at: calendar.starts_at(date),
                booking: booking, membership: (memberships[[program.id, booking.user_id]] if booking))
  end

  def bookings
    @bookings ||= Booking.where(:program_id.in => @programs.map(&:id), status: 'confirmed',
                                :date.gte => Date.current - 1, :date.lte => Date.current + @days + 1)
                         .includes(:user).index_by { |booking| [booking.program_id, booking.date] }
  end

  def memberships
    @memberships ||= begin
      selectors = bookings.values.group_by(&:program_id).map do |program_id, records|
        { program_id: program_id, :user_id.in => records.map(&:user_id).uniq }
      end
      ProgramMembership.participants.any_of(*selectors)
                       .only(:id, :program_id, :user_id, :display_name_override, :instagram_hidden)
                       .index_by { |membership| [membership.program_id, membership.user_id] }
    end
  end

  def exceptions
    @exceptions ||= begin
      from = @programs.map { |program| local_month_start(program) }.min
      ProgramScheduleException.where(:program_id.in => @programs.map(&:id), :date.gte => from)
                              .group_by(&:program_id)
    end
  end

  def local_month_start(program)
    Time.current.in_time_zone(program.time_zone).to_date.beginning_of_month.beginning_of_week(:sunday)
  end
end
