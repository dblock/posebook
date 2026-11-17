# frozen_string_literal: true

class NotificationContent
  include ProgramCalendarHelper

  def initialize(scope, recipient)
    @program = scope if scope.is_a?(Program)
    @venue = scope.is_a?(Venue) ? scope : @program&.venue
    @recipient = recipient
  end

  def values
    recipient_values.merge(program_values).merge(
      'program_name' => @program&.name.to_s, 'venue_name' => @venue&.name.to_s,
      'target_name' => (@program || @venue)&.name.to_s, 'coordinator_label' => 'coordinator',
      'admission_source' => 'A participation application', 'reminder_days' => '7'
    )
  end

  private

  def recipient_values
    name = @recipient.respond_to?(:name) ? @recipient.name : 'Participant'
    { 'recipient_name' => name, 'participant_name' => name,
      'recipient_email' => @recipient.respond_to?(:email) ? @recipient.email : @recipient.to_s }
  end

  def program_values
    { 'participant_label' => @program&.participant_label || 'Participant',
      'participant_article' => @program&.participant_article || 'a',
      'regular_schedule' => @program ? program_schedule_summary(@program) : '' }
  end
end
