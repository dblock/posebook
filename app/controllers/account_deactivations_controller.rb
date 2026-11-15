# frozen_string_literal: true

class AccountDeactivationsController < ApplicationController
  before_action :require_authentication
  before_action -> { @user = current_user }

  def new
    redirect_to security_profile_path(anchor: 'deactivate-account')
  end

  def create
    if @user.password_matches?(params[:current_password]) && @user.deactivate
      reset_session
      redirect_to new_session_path, notice: t('accounts.deactivated')
    else
      render 'profiles/security', status: :unprocessable_content
    end
  end
end
