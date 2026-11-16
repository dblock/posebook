# frozen_string_literal: true

module Admin
  class UsersController < ApplicationController
    include UserPages

    before_action :require_authentication
    before_action :require_system_admin
    before_action -> { response.headers['Cache-Control'] = 'private, no-store' }
    before_action :find_user, except: :index
    before_action :redirect_own_account, except: %i[index update password_reset]

    def index
      @users = User.order_by(name: :asc)
    end

    def show = render('profiles/show')

    def bookings
      load_user_bookings(@user)
      render 'profiles/bookings'
    end

    def programs
      load_user_programs(@user)
      render 'profiles/programs'
    end

    def applications
      load_user_applications(@user)
      render 'participant_applications/index'
    end

    def history
      load_user_history(@user)
      render 'profiles/history'
    end

    def photos
      @gallery = PhotoGallery.new(@user, current_user)
      @photos = @gallery.photos
      render 'participant_profiles/photos'
    end

    def security; end

    def password_reset
      return redirect_to(security_admin_user_path(@user), alert: t('password_resets.unavailable')) unless
        Rails.configuration.x.password_reset_delivery_enabled && @user.active?

      @user.send_password_reset
      redirect_to security_admin_user_path(@user), notice: t('password_resets.admin_queued', email: @user.email)
    rescue EmailDelivery::Unavailable => e
      NewRelic::Agent.notice_error(e)
      redirect_to security_admin_user_path(@user), alert: t('password_resets.failed')
    end

    def edit; end

    def update
      return update_access if params.key?(:active)

      attributes = params.expect(user: %i[name email phone gender display_name instagram_handle
                                          instagram_tagging_allowed]).to_h.symbolize_keys
      if @user.update_by_admin(attributes)
        redirect_after_update
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def redirect_own_account
      return unless @user == current_user

      redirect_to(action_name == 'show' ? profile_path : public_send("#{action_name}_profile_path"))
    end

    def find_user
      @user = User.find(params.expect(:id))
    end

    def update_access
      active = params.expect(:active).to_s
      raise ActionController::BadRequest unless %w[true false].include?(active)

      result = active == 'true' ? @user.reactivate : @user.deactivate
      alert = @user.errors.full_messages.to_sentence.presence || t('accounts.status_update_failed')
      redirect_to access_return_path, result ? { notice: t('accounts.status_updated') } : { alert: alert }
    end

    def access_return_path
      params[:return_to] == 'security' ? security_admin_user_path(@user) : admin_users_path
    end

    def redirect_after_update
      if @user.id == current_user.id && @user.session_version != current_user.session_version
        reset_session
        redirect_to new_session_path, notice: t('accounts.user_email_updated')
      else
        redirect_to edit_admin_user_path(@user), notice: t('accounts.user_updated')
      end
    end
  end
end
