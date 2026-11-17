# frozen_string_literal: true

class BookingReminderPreferencesController < ApplicationController
  before_action do
    response.headers['Cache-Control'] = 'private, no-store'
    @user = User.for_booking_reminder_token(params[:token])
    head :not_found unless @user
  end

  def show; end

  def update
    @user.update!(booking_reminders_enabled: false)
    redirect_to booking_reminder_preference_path(token: params[:token]), notice: t('booking_notifications.unsubscribed')
  end
end
