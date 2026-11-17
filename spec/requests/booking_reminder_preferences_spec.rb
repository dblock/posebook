# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Booking reminder preferences', :aggregate_failures, :database, type: :request do
  it 'requires an explicit action to unsubscribe and rejects altered tokens' do
    user = create_user
    token = user.booking_reminder_token
    get booking_reminder_preference_path(token: token)
    expect(response).to have_http_status(:ok)
    expect(user.reload.booking_reminders_enabled?).to be(true)
    patch booking_reminder_preference_path(token: "#{token}changed")
    expect(response).to have_http_status(:not_found)
    expect(user.reload.booking_reminders_enabled?).to be(true)
    patch booking_reminder_preference_path(token: token)
    expect(response).to have_http_status(:redirect)
    expect(user.reload.booking_reminders_enabled?).to be(false)
  end
end
