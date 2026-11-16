# frozen_string_literal: true

# Renders a duplicate custom slug as a form error on the controller's program or venue.
module SlugConflictHandling
  extend ActiveSupport::Concern

  included do
    rescue_from Mongo::Error::OperationFailure, with: :handle_slug_conflict
  end

  private

  def handle_slug_conflict(error)
    raise error unless error.code == 11_000

    instance_variable_get("@#{controller_name.singularize}").errors.add(:custom_slug, :taken)
    render(action_name == 'create' ? :new : :edit, status: :unprocessable_content)
  end
end
