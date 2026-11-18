# frozen_string_literal: true

require 'simplecov'
SimpleCov.start

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  config.example_status_persistence_file_path = '.rspec_status'
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
end
