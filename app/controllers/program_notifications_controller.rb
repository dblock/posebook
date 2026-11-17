# frozen_string_literal: true

class ProgramNotificationsController < NotificationSettingsController
  private

  def find_scope
    response.headers['Cache-Control'] = 'private, no-store'
    @notification_scope = @program = Program.managed_by(current_user).find(params.expect(:program_id))
  end
end
