# frozen_string_literal: true

ENV['RAILS_ENV'] = 'test'
require_relative 'spec_helper'
require_relative '../config/environment'
require 'rspec/rails'

RSpec.configure do |config|
  config.before(:suite) do
    database = Mongoid.default_client.database.name
    raise "Refusing to test against database #{database.inspect}" unless database.match?(/\Aposebook_test(?:_|\z)/)
  end
end
