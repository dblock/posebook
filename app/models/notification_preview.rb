# frozen_string_literal: true

class NotificationPreview
  def initialize(scope, setting, **options)
    @scope = scope
    @setting = setting
    @url_options = options.fetch(:url_options)
    @program = scope.is_a?(Program) ? scope : sample_program
    @booking_preview = BookingNotificationPreview.new(@program, setting, **options) if
      NotificationCatalog::BOOKING_KINDS.include?(setting.kind)
  end

  def content
    return @booking_preview.content if @booking_preview

    user = User.new(name: 'Alex Example', email: 'alex@example.test')
    values = NotificationContent.new(@program, user).values.merge(sample_values)
    @setting.render(values)
  end

  def timing
    return @booking_preview.timing if @booking_preview
    return "#{@setting.days_after} elapsed days after the draft is first saved or reopened" if
      @setting.kind == 'application_draft'

    'Queued immediately after the action'
  end

  def recipient
    return @booking_preview.recipient if @booking_preview
    return 'Assigned coordinators' if NotificationCatalog::COORDINATOR_ONLY.include?(@setting.kind)

    'alex@example.test'
  end

  private

  def sample_program
    venue = @scope.is_a?(Venue) ? @scope : Venue.new(name: 'Example Studio', address: '123 Example Street')
    Program.new(name: 'Example Program', venue: venue, time_zone: 'America/New_York',
                available_weekdays: ['1'], start_time: '18:30', end_time: '21:00')
  end

  def sample_values
    base = "#{@url_options.fetch(:protocol)}#{@url_options.fetch(:host)}"
    base += ":#{@url_options[:port]}" if @url_options[:port]
    urls = NotificationCatalog::REQUIRED_LINKS.fetch(@setting.kind, []).index_with do |name|
      "#{base}/#{name.delete_suffix('_url')}/preview"
    end
    role = @setting.kind == 'venue_coordinator_invitation' ? 'venue coordinator' : 'program coordinator'
    urls.merge('participant_name' => 'Alex Example', 'reminder_days' => @setting.days_after.to_s,
               'target_name' => (@scope.is_a?(Venue) ? @scope.name : @program.name),
               'coordinator_label' => role)
  end
end
