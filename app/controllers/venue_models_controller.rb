# frozen_string_literal: true

class VenueModelsController < ApplicationController
  before_action :require_authentication
  before_action -> { @venue = Venue.managed_by(current_user).find(params.expect(:venue_id)) }
  rescue_from BookingMutation::Invalid, with: :show_error

  def index
    @roster = VenueModelRoster.new(@venue, page: params[:page])
    @memberships = @roster.memberships
  end

  def invite
    result = delivery.call(params.expect(:id))
    redirect_to roster_path,
                result == :failed ? { alert: t('model_access.email_failed') } : { notice: t("model_access.#{result}") }
  end

  def invite_all
    results = @venue.memberships.models.map { |membership| delivery.call(membership.id) }.tally
    redirect_to roster_path, notice: t('model_access.bulk_result', sent: results.fetch(:sent, 0),
                                                                   failed: results.fetch(:failed, 0),
                                                                   skipped: results.fetch(:skipped, 0))
  end

  def pause
    mutation.pause(params.expect(:id), params.permit(:reason)[:reason])
    redirect_to roster_path, notice: t('model_access.pause_saved')
  end

  def resume
    mutation.resume(params.expect(:id))
    redirect_to roster_path, notice: t('model_access.resumed')
  end

  private

  def roster_path
    venue_models_path(@venue, page: params[:page])
  end

  def mutation
    ModelAccessMutation.new(venue: @venue, user: current_user)
  end

  def delivery
    BookingInvitationDelivery.new(venue: @venue, user: current_user)
  end

  def show_error(error)
    redirect_to roster_path, alert: error.message
  end
end
