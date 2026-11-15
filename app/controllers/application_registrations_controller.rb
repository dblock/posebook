# frozen_string_literal: true

class ApplicationRegistrationsController < ApplicationController
  before_action :find_program
  rate_limit to: 5, within: 5.minutes, only: :create
  rescue_from EmailDelivery::Unavailable, with: :delivery_unavailable
  rescue_from Mongoid::Errors::Validations, with: :invalid_registration

  def new
    session[:application_program] = @program.id.to_s unless current_user
    session.delete(:application_status)
    session.delete(:application_review)
    @registration = ApplicationRegistration.new(email: current_user&.email)
  end

  def create
    @registration = ApplicationRegistration.new(program: @program, **registration_attributes)
    return render :new, status: :unprocessable_content unless @registration.valid?
    return delivery_unavailable unless Rails.configuration.x.password_reset_delivery_enabled

    EmailDelivery.enqueue('application_registration', @registration, token: @registration.token,
                                                                     expires_at: @registration.expires_at) do
      @registration.save!
    end
    redirect_to new_program_application_registration_path(@program),
                notice: t('application_registration.queued')
  end

  private

  def registration_attributes
    params.expect(application_registration: [:email]).to_h
  end

  def find_program
    @program = Program.find(params.expect(:program_id))
    head :not_found unless @program.applications_enabled? && @program.booking_active?
    response.headers['Cache-Control'] = 'private, no-store'
  end

  def delivery_unavailable
    @registration.errors.add(:base, t('application_registration.unavailable'))
    render :new, status: :service_unavailable
  end

  def invalid_registration(error)
    raise error unless error.document == @registration

    render :new, status: :unprocessable_content
  end
end
