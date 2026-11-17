# frozen_string_literal: true

module NotificationsHelper
  def notification_list_path(scope)
    return program_notifications_path(scope) if scope.is_a?(Program)
    return venue_notifications_path(scope) if scope.is_a?(Venue)

    admin_settings_notifications_path
  end

  def notification_edit_path(scope, kind)
    return edit_program_notification_path(scope, kind) if scope.is_a?(Program)
    return edit_venue_notification_path(scope, kind) if scope.is_a?(Venue)

    edit_admin_settings_notification_path(kind)
  end

  def notification_update_path(scope, kind)
    return program_notification_path(scope, kind) if scope.is_a?(Program)
    return venue_notification_path(scope, kind) if scope.is_a?(Venue)

    admin_settings_notification_path(kind)
  end

  def notification_preview_path(scope, kind)
    return preview_program_notification_path(scope, kind) if scope.is_a?(Program)
    return preview_venue_notification_path(scope, kind) if scope.is_a?(Venue)

    preview_admin_settings_notification_path(kind)
  end

  def notification_navigation(scope)
    return render('programs/navigation', program: scope, active: 'notifications') if scope.is_a?(Program)
    return render('venues/navigation', venue: scope, active: 'notifications') if scope.is_a?(Venue)

    render 'shared/page_navigation', breadcrumbs: [['Admin Settings', admin_settings_path], ['Notifications', nil]],
                                     tabs: [['notifications', 'Notifications', admin_settings_notifications_path]],
                                     active: 'notifications', tabs_class: 'admin-settings-tabs',
                                     label: 'Admin settings navigation'
  end

  def notification_parent_label(scope)
    return 'Venue Defaults' if scope.is_a?(Program)
    return 'Admin Defaults' if scope.is_a?(Venue)

    'Built-In Defaults'
  end
end
