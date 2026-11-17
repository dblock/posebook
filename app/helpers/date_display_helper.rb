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
    return localized_calendar_date(value.to_date, '%B %Y') if format == :month

    date = localized_calendar_date(value.to_date, '%A, %B %-d, %Y')
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

  def localized_calendar_date(date, format)
    dates = @localized_calendar_dates ||= {}
    key = [I18n.locale, date, format]
    dates.fetch(key) { dates[key] = l(date, format: format) }
  end

  def absolute_date_label(value, today, format:)
    pattern = { compact: '%b %-d', month: '%B' }.fetch(format, '%a, %b %-d')
    pattern += format == :month ? ' %Y' : ', %Y' if value.year != today.year
    localized_calendar_date(value.to_date, pattern)
  end

  def nearby_date_label(date, today, compact:)
    offset = (date - today).to_i
    return { -1 => 'Yesterday', 0 => 'Today', 1 => 'Tomorrow' }[offset] if offset.abs <= 1
    return unless offset.abs < 7

    "#{offset.negative? ? 'Last' : 'Next'} #{localized_calendar_date(date, compact ? '%a' : '%A')}"
  end
end
