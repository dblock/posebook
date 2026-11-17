# frozen_string_literal: true

class VenueNotificationsController < NotificationSettingsController
  private

  def find_scope
    response.headers['Cache-Control'] = 'private, no-store'
    @notification_scope = @venue = Venue.coordinated_by(current_user).find(params.expect(:venue_id))
  end
end
