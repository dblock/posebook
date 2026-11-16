# frozen_string_literal: true

class CursorPage
  PER_PAGE = 50

  attr_reader :cursor

  def initialize(criteria, cursor: nil, per_page: PER_PAGE)
    @criteria = criteria
    @per_page = per_page
    @field, @direction = criteria.options.fetch(:sort).first
    @purpose = Digest::SHA256.hexdigest([criteria.klass.name, criteria.selector, @field, @direction].to_json)
    @position = verifier.verified(cursor, purpose: @purpose) if cursor.is_a?(String)
    @cursor = cursor if @position
  end

  def records
    @records ||= begin
      results = ordered(backwards?).limit(@per_page + 1).scroll(decoded_cursor).to_a
      @more = results.size > @per_page
      results = results.first(@per_page)
      backwards? ? results.reverse : results
    end
  end

  def next_cursor
    return if records.empty?
    return unless backwards? ? beyond?(records.last, false) : @more

    encode(records.last, false)
  end

  def previous_cursor
    return if records.empty?
    return unless backwards? ? @more : beyond?(records.first, true)

    encode(records.first, true)
  end

  private

  def backwards?
    @position&.fetch('backwards') || false
  end

  def ordered(backwards)
    # Forward scrolls in either order preserve ID ties and eager loading, unlike the previous aggregation.
    @criteria.reorder(@field => backwards ? -@direction : @direction)
  end

  def position(record, backwards)
    Mongoid::Scroll::Cursor.from_record(
      record, field: @criteria.klass.fields.fetch(@field),
              direction: backwards ? -@direction : @direction
    )
  end

  def decoded_cursor
    return unless @position

    cursor = Mongoid::Scroll::Cursor.new(@position.fetch('position'), field: @criteria.klass.fields.fetch(@field),
                                                                      direction: backwards? ? -@direction : @direction)
    # Float decoding can fall just below a stored millisecond and include the boundary row again.
    cursor.value = cursor.value.round(3) if cursor.value.is_a?(Time)
    cursor
  end

  def beyond?(record, backwards)
    ordered(backwards).scroll(position(record, backwards)).exists?
  end

  def encode(record, backwards)
    verifier.generate({ 'position' => position(record, backwards).to_s, 'backwards' => backwards }, purpose: @purpose)
  end

  def verifier
    Rails.application.message_verifier('pagination')
  end
end
