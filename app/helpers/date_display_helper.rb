# frozen_string_literal: true

module DateDisplayHelper
  def date_display_value(value, zone:)
    date_display_time?(value) ? value.in_time_zone(zone) : value
  end

  def date_display_time?(value)
    value.respond_to?(:hour)
  end

  def date_display_datetime(value, format:)
    return value.strftime('%Y-%m') if format == :month

    date_display_time?(value) ? value.iso8601(9) : value.iso8601
  end

  def date_display_title(value, format:)
    return l(value.to_date, format: '%B %Y') if format == :month

    date = l(value.to_date, format: '%A, %B %-d, %Y')
    return date unless date_display_time?(value)

    "#{date} at #{value.strftime('%-I:%M %p %Z')}"
  end

  def date_display_label(value, zone:, format:)
    return value.day.to_s if format == :day

    today = Time.current.in_time_zone(zone).to_date
    return absolute_date_label(value, today, format: format) if format == :month

    nearby_date_label(value.to_date, today, compact: format == :compact) ||
      absolute_date_label(value, today, format: format)
  end

  private

  def absolute_date_label(value, today, format:)
    pattern = { compact: '%b %-d', month: '%B' }.fetch(format, '%a, %b %-d')
    pattern += format == :month ? ' %Y' : ', %Y' if value.year != today.year
    l(value.to_date, format: pattern)
  end

  def nearby_date_label(date, today, compact:)
    offset = (date - today).to_i
    return { -1 => 'Yesterday', 0 => 'Today', 1 => 'Tomorrow' }[offset] if offset.abs <= 1
    return unless offset.abs < 7

    "#{offset.negative? ? 'Last' : 'Next'} #{l(date, format: compact ? '%a' : '%A')}"
  end
end
