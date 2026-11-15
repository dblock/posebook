# frozen_string_literal: true

class ProfilesController < ApplicationController
  before_action :require_authentication
  before_action -> { @user = current_user }

  def show
    @dashboard = ParticipantDashboard.new(@user)
    request.env['posebook.dashboard'] = @dashboard
  end

  def history
    @history = ParticipantHistory.new(@user, page: params[:page])
    @bookings = @history.bookings
  end

  def edit; end

  def details; end

  def security; end

  def update
    attributes = params.expect(user: %i[name email phone gender current_password display_name instagram_handle
                                        instagram_tagging_allowed public_profile_private]).to_h.symbolize_keys
    if (updated = @user.update_profile(attributes))
      redirect_to details_profile_path,
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
