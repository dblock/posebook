# frozen_string_literal: true

class VenueModelRoster
  PER_PAGE = 25

  attr_reader :page

  def initialize(venue, page:)
    @venue = venue
    @page = page.to_s.to_i.clamp(1, total_pages)
  end

  def memberships
    models.includes(:user).order_by(created_at: :asc, id: :asc).skip(offset).limit(PER_PAGE)
  end

  def counts
    @counts ||= begin
      total = models.count
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

  def models
    @venue.memberships.models
  end

  def active
    @active ||= begin
      active_ids = User.active.where(:id.in => models.distinct(:user_id)).pluck(:id)
      models.where(:user_id.in => active_ids)
    end
  end

  def unpaused
    active.where(:model_paused.ne => true)
  end

  def available
    unpaused.where(:user_id.nin => @venue.model_bookings.upcoming.distinct(:user_id))
  end

  def offset
    (page - 1) * PER_PAGE
  end
end
