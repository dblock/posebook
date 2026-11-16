# frozen_string_literal: true

module ApplicationHelper
  STATUS_LABEL_TONES = {
    'confirmed' => 'success', 'completed' => 'success', 'active' => 'success', 'available' => 'success',
    'accepted' => 'success', 'public' => 'success', 'open' => 'success', 'enabled' => 'success',
    'invited' => 'success',
    'canceled' => 'danger', 'revoked' => 'danger', 'inactive' => 'danger',
    'closed' => 'danger', 'declined' => 'danger',
    'pending' => 'warning', 'paused' => 'warning', 'rescheduled' => 'warning', 'uninvited' => 'warning',
    'booked' => 'warning', 'tentative' => 'warning', 'private' => 'private'
  }.freeze

  def user_page_path(user, page = 'profile', **params)
    if user == current_user
      page == 'profile' ? profile_path(**params) : public_send("#{page}_profile_path", **params)
    else
      page == 'profile' ? admin_user_path(user, **params) : public_send("#{page}_admin_user_path", user, **params)
    end
  end

  def status_label(status, **attributes)
    tone = STATUS_LABEL_TONES.fetch(status.to_s.downcase, 'neutral')
    attributes[:class] = class_names('status-label', "status-label-#{tone}", attributes[:class])
    tag.span(status, **attributes)
  end

  def copy_button(label:, target:)
    render 'shared/copy_button', target: target, label: label
  end
end
