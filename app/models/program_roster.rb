# frozen_string_literal: true

class ProgramRoster
  PER_PAGE = 25
  STATUSES = %w[all available booked paused inactive].freeze

  attr_reader :pagination, :status

  def initialize(program, cursor: nil, status: 'all')
    @program = program
    @status = status
    @pagination = CursorPage.new(filtered_participants.includes(:user).order_by(created_at: :asc),
                                 cursor: cursor, per_page: PER_PAGE)
  end

  def memberships
    pagination.records
  end

  def access_for(membership)
    @access ||= memberships.index_with do |member|
      BookingAccess.new(member, booking: upcoming_bookings[member.user_id]&.first,
                                allowed: booking_allowed?(member))
    end
    @access.fetch(membership)
  end

  def counts
    @counts ||= begin
      total = participants.count
      active_count = active.count
      unpaused_count = unpaused.count
      available_count = available.count
      { total: total, available: available_count, booked: unpaused_count - available_count,
        paused: active_count - unpaused_count, inactive: total - active_count }
    end
  end

  private

  def filtered_participants
    case status
    when 'available' then available
    when 'booked' then unpaused.where(:user_id.in => @program.bookings.upcoming.distinct(:user_id))
    when 'paused' then active.where(participant_paused: true)
    when 'inactive' then participants.where(:user_id.nin => active.distinct(:user_id))
    else participants
    end
  end

  def upcoming_bookings
    @upcoming_bookings ||= begin
      records = Booking.where(program_id: @program.id, :user_id.in => memberships.map(&:user_id))
      records.upcoming.order_by(id: :asc).to_a.group_by(&:user_id)
    end
  end

  def booking_history
    @booking_history ||= Booking.collection.aggregate(history_pipeline).index_by { |record| record['_id'] }
  end

  def history_pipeline
    completed = { '$and' => [{ '$eq' => ['$status', 'confirmed'] }, { '$lte' => ['$ends_at', Time.current] }] }
    [
      { '$match' => { 'program_id' => @program.id,
                      'user_id' => { '$in' => memberships.map(&:user_id) } } },
      { '$group' => {
        '_id' => '$user_id',
        'created_at' => { '$max' => '$created_at' },
        'completed_at' => { '$max' => { '$cond' => [completed, '$ends_at', nil] } }
      } }
    ]
  end

  def booking_allowed?(member)
    return false unless member.user.active? && !member.participant_paused

    previous = booking_history.fetch(member.user_id, {})
    invited_at = member.booking_invited_at || previous['created_at']
    invited_at.present? && (previous['completed_at'].nil? || previous['completed_at'] <= invited_at)
  end

  def participants
    @program.memberships.participants
  end

  def active
    @active ||= begin
      active_ids = User.active.where(:id.in => participants.distinct(:user_id)).pluck(:id)
      participants.where(:user_id.in => active_ids)
    end
  end

  def unpaused
    @unpaused ||= active.where(:participant_paused.ne => true)
  end

  def available
    @available ||= unpaused.where(:user_id.nin => @program.bookings.upcoming.distinct(:user_id))
  end
end
