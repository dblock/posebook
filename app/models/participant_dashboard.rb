# frozen_string_literal: true

class ParticipantDashboard
  def initialize(user)
    @user = user
  end

  def upcoming_bookings
    @upcoming_bookings ||= begin
      bookings = Booking.upcoming.where(user_id: @user.id, :program_id.in => memberships.keys)
                        .includes(program: :venue).to_a.sort_by(&:scheduled_start)
      Venue.preload_primary_photos(bookings.map { |booking| booking.program.venue }.uniq(&:id), series: true)
      bookings
    end
  end

  def access_for(program_id)
    @access ||= begin
      bookings = upcoming_bookings.group_by(&:program_id)
      memberships.transform_values do |membership|
        BookingAccess.new(membership, booking: bookings[membership.program_id]&.first,
                                      allowed: booking_allowed?(membership))
      end
    end
    @access.fetch(program_id)
  end

  def applications
    @applications ||= ParticipantApplication.where(user_id: @user.id).includes(program: :venue)
                                            .order_by(created_at: :desc, id: :desc).to_a
  end

  def bookable_programs
    @bookable_programs ||= begin
      booked = upcoming_bookings.map(&:program_id)
      programs = memberships.values.filter_map do |membership|
        membership.program if booked.exclude?(membership.program_id) && access_for(membership.program_id).allowed?
      end.sort_by(&:name)
      Program.preload_primary_photos(programs, series: true)
    end
  end

  def participating_programs
    @participating_programs ||= begin
      ids = Program.viewable_by(@user).where(:id.in => memberships.keys).distinct(:id).to_set
      programs = memberships.values.filter_map do |membership|
        membership.program if ids.include?(membership.program_id)
      end.sort_by(&:name)
      Program.preload_primary_photos(programs, series: true)
    end
  end

  def managed_program_ids
    @managed_program_ids ||= if upcoming_bookings.empty?
                               []
                             else
                               Program.managed_by(@user).where(:id.in => upcoming_bookings.map(&:program_id))
                                      .distinct(:id)
                             end
  end

  def organizer_contacts_for(program_id)
    organizer_contacts.fetch(program_id, [])
  end

  private

  def organizer_contacts
    @organizer_contacts ||= begin
      ids = upcoming_bookings.select(&:rescheduling_locked?).map(&:program_id)
      records = ProgramMembership.coordinators.where(:program_id.in => ids).includes(:user)
      records.group_by(&:program_id).transform_values { |members| active_contacts(members) }
    end
  end

  def active_contacts(members)
    members.filter_map(&:user).select(&:active?).sort_by(&:name)
  end

  def memberships
    @memberships ||= ProgramMembership.participants.where(user_id: @user.id)
                                      .includes(program: :venue).index_by(&:program_id)
  end

  def booking_allowed?(membership)
    return false unless @user.active? && !membership.participant_paused && membership.program.booking_active?

    previous = booking_history.fetch(membership.program_id, {})
    invited_at = membership.booking_invited_at || previous['created_at']
    invited_at.present? && (previous['completed_at'].nil? || previous['completed_at'] <= invited_at)
  end

  def booking_history
    @booking_history ||= begin
      completed = { '$and' => [{ '$eq' => ['$status', 'confirmed'] }, { '$lte' => ['$ends_at', Time.current] }] }
      pipeline = [
        { '$match' => { 'user_id' => @user.id, 'program_id' => { '$in' => memberships.keys } } },
        { '$group' => {
          '_id' => '$program_id', 'created_at' => { '$max' => '$created_at' },
          'completed_at' => { '$max' => { '$cond' => [completed, '$ends_at', nil] } }
        } }
      ]
      Booking.collection.aggregate(pipeline).index_by { |record| record['_id'] }
    end
  end
end
