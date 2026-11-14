# frozen_string_literal: true

module Admin
  class UsersController < ApplicationController
    before_action :require_authentication
    before_action :require_system_admin
    before_action :find_user, only: %i[edit update]

    def index
      @users = User.order_by(name: :asc)
    end

    def edit; end

    def update
      return update_access if params.key?(:active)

      attributes = params.expect(user: %i[name email phone display_name instagram_handle
                                          instagram_tagging_allowed public_profile_private]).to_h.symbolize_keys
      if @user.update_by_admin(attributes)
        redirect_after_update
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def find_user
      @user = User.find(params.expect(:id))
    end

    def update_access
      active = params.expect(:active).to_s
      raise ActionController::BadRequest unless %w[true false].include?(active)

      result = active == 'true' ? @user.reactivate : @user.deactivate
      redirect_to admin_users_path,
                  result ? { notice: t('accounts.status_updated') } : { alert: @user.errors.full_messages.to_sentence }
    end

    def redirect_after_update
      if @user.id == current_user.id && @user.session_version != current_user.session_version
        reset_session
        redirect_to new_session_path, notice: t('accounts.user_email_updated')
      else
        redirect_to admin_users_path, notice: t('accounts.user_updated')
      end
    end
  end
end
