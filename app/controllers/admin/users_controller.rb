# frozen_string_literal: true

module Admin
  class UsersController < ApplicationController
    before_action :require_authentication
    before_action :require_system_admin

    def index
      @users = User.order_by(name: :asc)
    end

    def update
      user = User.find(params.expect(:id))
      result = params[:active] == 'true' ? user.reactivate : user.deactivate
      redirect_to admin_users_path,
                  result ? { notice: t('accounts.status_updated') } : { alert: user.errors.full_messages.to_sentence }
    end
  end
end
