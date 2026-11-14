# frozen_string_literal: true

require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.public_file_server.headers = { 'cache-control' => "public, max-age=#{1.year.to_i}" }
  config.assume_ssl = true
  config.force_ssl = true
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == '/up' } } }
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger($stdout)
  config.log_level = ENV.fetch('RAILS_LOG_LEVEL', 'info')
  config.silence_healthcheck_path = '/up'
  config.active_support.report_deprecations = false
  config.x.password_reset_delivery_enabled = ENV['SMTP_ADDRESS'].present? && ENV['MAIL_FROM'].present?
  config.action_mailer.perform_deliveries = config.x.password_reset_delivery_enabled
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: ENV.fetch('SMTP_ADDRESS', nil), port: ENV.fetch('SMTP_PORT', 587).to_i,
    domain: ENV.fetch('APP_HOST', 'enochs.dblock.org'),
    user_name: ENV.fetch('SMTP_USERNAME', nil), password: ENV.fetch('SMTP_PASSWORD', nil),
    authentication: ENV['SMTP_USERNAME'].present? ? :plain : nil, enable_starttls_auto: true,
    open_timeout: 5, read_timeout: 5
  }
  config.action_mailer.default_url_options = { host: ENV.fetch('APP_HOST', 'enochs.dblock.org'), protocol: 'https' }
  config.i18n.fallbacks = true
  config.hosts = ENV.fetch('APP_HOST', 'enochs.dblock.org').split(',')
  config.host_authorization = { exclude: ->(request) { request.path == '/up' } }
end
