# frozen_string_literal: true

class RegistrationsController < ApplicationController
  before_action :require_blank_installation
  rate_limit to: 5, within: 5.minutes, only: :create

  def new
    @user = User.new(instagram_tagging_allowed: true)
  end

  def create
    attributes = params.expect(user: %i[name email phone gender password password_confirmation
                                        display_name instagram_handle instagram_tagging_allowed])
    @user = User.bootstrap(attributes)
    if @user.persisted?
      start_session(@user)
      redirect_to root_path, notice: t('accounts.created')
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def require_blank_installation
    redirect_to new_session_path, alert: t('accounts.invitation_required') if User.exists?
  end
end
