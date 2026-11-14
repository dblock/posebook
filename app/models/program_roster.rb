# frozen_string_literal: true

class ProgramRoster
  PER_PAGE = 25

  attr_reader :page

  def initialize(program, page:)
    @program = program
    @page = page.to_s.to_i.clamp(1, total_pages)
  end

  def memberships
    @memberships ||= participants.includes(:user).order_by(created_at: :asc, id: :asc).skip(offset).limit(PER_PAGE).to_a
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

  def total_pages
    [(counts[:total].to_f / PER_PAGE).ceil, 1].max
  end

  def first_number
    counts[:total].zero? ? 0 : offset + 1
  end

  def last_number
    [offset + PER_PAGE, counts[:total]].min
  end

  private

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
    active.where(:participant_paused.ne => true)
  end

  def available
    unpaused.where(:user_id.nin => @program.bookings.upcoming.distinct(:user_id))
  end

  def offset
    (page - 1) * PER_PAGE
  end
end
