# frozen_string_literal: true

class PasswordsController < ApplicationController
  before_action :require_authentication

  def update
    @user = current_user
    attributes = params.expect(user: %i[current_password password password_confirmation]).to_h.symbolize_keys
    if @user.change_password(attributes)
      start_session(@user.reload)
      redirect_to edit_profile_path, notice: t('profiles.password_updated')
    else
      render 'profiles/edit', status: :unprocessable_content
    end
  end
end
