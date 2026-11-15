# frozen_string_literal: true

class ProfilesController < ApplicationController
  before_action :require_authentication
  before_action -> { @user = current_user }

  def show; end

  def edit; end

  def security; end

  def update
    attributes = params.expect(user: %i[name email phone gender current_password display_name instagram_handle
                                        instagram_tagging_allowed public_profile_private]).to_h.symbolize_keys
    if @user.update_profile(attributes)
      redirect_to profile_path, notice: t('profiles.updated')
    else
      render :edit, status: :unprocessable_content
    end
  rescue IOError, SystemCallError, Timeout::Error, Net::SMTPError => e
    NewRelic::Agent.notice_error(e)
    @user.errors.add(:base, t('password_resets.failed'))
    render :edit, status: :service_unavailable
  end
end
