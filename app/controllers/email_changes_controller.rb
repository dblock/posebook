# frozen_string_literal: true

class EmailChangesController < ApplicationController
  before_action :find_user

  def show; end

  def update
    if @user.confirm_email_change(params[:token])
      reset_session
      redirect_to new_session_path, notice: t('email_changes.updated')
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  def find_user
    if params[:token].present?
      @user = User.active.where(
        email_change_digest: Digest::SHA256.hexdigest(params[:token].to_s),
        :email_change_expires_at.gt => Time.current
      ).first
    end
    redirect_to new_session_path, alert: t('email_changes.invalid') unless @user
  end
end
