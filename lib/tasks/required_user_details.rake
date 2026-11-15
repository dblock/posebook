# frozen_string_literal: true

namespace :users do
  desc 'Fill missing phone and gender values before requiring them'
  task backfill_required_details: :environment do
    RequiredUserDetailsMigration.call
  end
end
