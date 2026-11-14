# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'
require_relative 'spec_helper'
require_relative '../config/environment'
require 'rspec/rails'
require_relative 'support/database_helpers'

RSpec.configure do |config|
  config.include DatabaseHelpers, :database
  config.before(:suite) do
    database = Mongoid.default_client.database.name
    raise "Refusing to test against database #{database.inspect}" unless database.match?(/\Aposebook_test(?:_|\z)/)

    User.create_indexes
    VenueMembership.create_indexes
    ActiveModel::SecurePassword.min_cost = true
  end
  config.before(:each, :database) { ActionMailer::Base.deliveries.clear }
  config.after(:each, :database) { tracked_records.reverse_each { |record| record.destroy if record.persisted? } }
end
