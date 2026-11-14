# frozen_string_literal: true

module ApplicationHelper
  STATUS_LABEL_TONES = {
    'confirmed' => 'success', 'completed' => 'success', 'active' => 'success', 'available' => 'success',
    'accepted' => 'success', 'public' => 'success', 'open' => 'success', 'enabled' => 'success',
    'invited to book' => 'success',
    'canceled' => 'danger', 'revoked' => 'danger', 'inactive' => 'danger', 'inactive account' => 'danger',
    'closed' => 'danger',
    'pending' => 'warning', 'paused' => 'warning', 'rescheduled' => 'warning', 'invitation required' => 'warning',
    'verification pending' => 'warning', 'attendance not confirmed - follow up asap' => 'warning'
  }.freeze

  def status_label(status, **attributes)
    tone = STATUS_LABEL_TONES.fetch(status.to_s.partition(':').first.downcase, 'neutral')
    attributes[:class] = class_names('status-label', "status-label-#{tone}", attributes[:class])
    tag.span(status, **attributes)
  end
end
