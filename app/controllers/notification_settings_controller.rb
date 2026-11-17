# frozen_string_literal: true

class NotificationSettingsController < ApplicationController
  include NotificationsHelper

  before_action :require_authentication
  before_action :find_scope
  before_action :prepare_notification, except: :index
  rescue_from LocationActivation::Forbidden, with: -> { head :forbidden }

  def index
    @settings = NotificationSetting.all_for(@notification_scope)
    render 'program_notifications/index'
  end

  def edit = render('program_notifications/edit')

  def preview
    assign_setting
    @setting.valid?
    status = @setting.errors.empty? ? :ok : :unprocessable_content
    return render partial: 'program_notifications/preview', status: status if
      request.headers['X-Notification-Preview'] == 'true'

    render 'program_notifications/edit', status: status
  end

  def update
    assign_setting
    if @setting.valid? && save_notification?
      return redirect_to notification_edit_path(@notification_scope, @setting.kind),
                         notice: t('booking_notifications.saved')
    end
    render 'program_notifications/edit', status: :unprocessable_content
  end

  private

  def prepare_notification
    kind = params.expect(:kind)
    return head :not_found unless NotificationCatalog.kinds_for(@notification_scope).include?(kind)

    @setting = NotificationSetting.for(@notification_scope, kind)
  end

  def assign_setting
    attributes = params.expect(notification: NotificationSetting::FIELDS.map(&:to_sym))
    attributes = @setting.parent_attributes.merge('subject' => nil, 'body' => nil) if params[:inherit] == '1'
    @setting.assign_attributes(attributes)
  end

  def save_notification?
    settings = { @setting.kind => @setting.stored_attributes }
    @notification_scope = NotificationSettingsUpdate.new(scope: @notification_scope, user: current_user).call(settings)
    @setting.errors.add(:base, @notification_scope.errors.full_messages.to_sentence) if @notification_scope.errors.any?
    @notification_scope.errors.empty?
  end
end
