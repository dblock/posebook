# frozen_string_literal: true

class AccountDeactivationsController < ApplicationController
  before_action :require_authentication

  def create
    @user = current_user
    if @user.password_matches?(params[:current_password]) && @user.deactivate
      reset_session
      redirect_to new_session_path, notice: t('accounts.deactivated')
    else
      render 'profiles/edit', status: :unprocessable_content
    end
  end
end
