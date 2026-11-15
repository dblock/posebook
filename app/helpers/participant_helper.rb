# frozen_string_literal: true

module ParticipantHelper
  def participant_option_label(participant, show_gender: false)
    parts = [participant.name, participant.email]
    parts << "@#{participant.instagram_handle}" if participant.instagram_handle.present?
    parts << (participant.gender&.capitalize || 'Gender not selected') if show_gender
    parts.join(' - ')
  end
end
