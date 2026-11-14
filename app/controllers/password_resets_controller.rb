# frozen_string_literal: true

require 'net/smtp'

class PasswordResetsController < ApplicationController
  before_action :find_user, only: %i[edit update]
  before_action :require_delivery, only: :create
  rate_limit to: 5, within: 15.minutes, only: :create

  def new; end

  def edit; end

  def create
    User.with_email(params[:email])&.send_password_reset
    redirect_to new_session_path, notice: t('password_resets.sent')
  rescue IOError, SystemCallError, Timeout::Error, Net::SMTPError => e
    NewRelic::Agent.notice_error(e)
    flash.now[:alert] = t('password_resets.failed')
    render :new, status: :service_unavailable
  end

  def update
    if @user.reset_password(params[:token], params.expect(user: %i[password password_confirmation]))
      reset_session
      redirect_to new_session_path, notice: t('password_resets.updated')
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def require_delivery
    return if Rails.configuration.x.password_reset_delivery_enabled

    flash.now[:alert] = t('password_resets.unavailable')
    render :new, status: :service_unavailable
  end

  def find_user
    @user = User.for_password_reset(params[:token])
    return if @user

    redirect_to new_password_reset_path, alert: t('password_resets.invalid')
  end
end
