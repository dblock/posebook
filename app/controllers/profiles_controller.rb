# frozen_string_literal: true

class ProfilesController < ApplicationController
  include UserPages

  helper_method :participant_dashboard
  before_action :require_authentication
  before_action -> { @user = current_user }

  def show; end

  def bookings = load_user_bookings(@user)

  def history = load_user_history(@user)

  def edit; end

  def details = redirect_to(profile_path)

  def security; end

  def notifications; end

  def update_notifications
    attributes = params.expect(user: NotificationPreferences::FIELDS.map(&:to_sym))
    if @user.update(attributes)
      redirect_to notifications_profile_path, notice: t('booking_notifications.saved')
    else
      render :notifications, status: :unprocessable_content
    end
  end

  def programs = load_user_programs(@user)

  def update
    attributes = params.expect(user: %i[name email phone gender current_password display_name instagram_handle
                                        instagram_tagging_allowed booking_reminders_enabled]).to_h.symbolize_keys
    if (updated = @user.update_profile(attributes))
      redirect_to profile_path,
                  notice: t(updated.is_a?(EmailDelivery) ? 'profiles.updated_email_queued' : 'profiles.updated')
    else
      render :edit, status: :unprocessable_content
    end
  rescue EmailDelivery::Unavailable => e
    NewRelic::Agent.notice_error(e)
    @user.errors.add(:base, t('password_resets.failed'))
    render :edit, status: :service_unavailable
  end
end
