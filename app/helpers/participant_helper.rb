# frozen_string_literal: true

module ParticipantHelper
  def participant_contact_label(participant)
    name = participant.name.presence
    email = participant.email.presence
    label = name && email ? "#{name} <#{email}>" : name || email || 'Personal invitation'
    gender = participant.try(:gender).presence
    gender ? "#{label} (#{gender.capitalize})" : label
  end
end
