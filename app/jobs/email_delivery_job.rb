# frozen_string_literal: true

class EmailDeliveryJob < ApplicationJob
  queue_as :mailers

  def perform(delivery_id)
    EmailDelivery.where(id: delivery_id).first&.deliver
  rescue StandardError => e
    raise EmailDelivery::Failed, e.class.name, cause: nil
  end
end
