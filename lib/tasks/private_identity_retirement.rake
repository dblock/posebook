# frozen_string_literal: true

namespace :users do
  desc 'Retire the private identity preference while preserving affected users\' privacy'
  task retire_private_identity: :environment do
    PrivateIdentityRetirement.call
  end
end
