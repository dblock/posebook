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
    Program.create_indexes
    Venue.create_indexes
    VenueMembership.create_indexes
    HistoryTracker.create_indexes
    ProgramScheduleException.create_indexes
    ProgramMembership.create_indexes
    ParticipantInvitation.create_indexes
    ParticipantApplication.create_indexes
    ApplicationRegistration.create_indexes
    ParticipationEvent.create_indexes
    Booking.create_indexes
    BookingClaim.create_indexes
    GoogleCalendarConnection.create_indexes
    GoogleCalendarSync.create_indexes
    QueuedJob.create_indexes
    EmailDelivery.create_indexes
    ProfilePhoto.storage.file_model.create_indexes
    ProfilePhoto.storage.chunk_model.create_indexes
    ActiveModel::SecurePassword.min_cost = true
  end
  config.before(:each, :database) { ActionMailer::Base.deliveries.clear }
  config.after(:each, :database) { cleanup_records }
end
