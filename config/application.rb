# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_job/railtie'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_view/railtie'

Bundler.require(*Rails.groups)

module Posebook
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])
    config.time_zone = 'UTC'
    config.active_job.queue_adapter = :async
    config.generators do |generators|
      generators.orm :mongoid
      generators.test_framework :rspec
      generators.system_tests = nil
    end
  end
end
