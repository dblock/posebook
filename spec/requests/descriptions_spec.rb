# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public descriptions', :aggregate_failures, :database, type: :request do
  let(:description) { "## Welcome\n\nBring **pencils** and [read more](https://example.test/visit)." }
  let(:venue) { create_venue(description: description) }
  let(:program) do
    create_program(venue: venue, description: description, instructions: 'Private arrival details',
                   pay: 321, booking_horizon_months: 9, applications_enabled: true)
  end
  let(:coordinator) { create_user }

  %i[venue program].each do |kind|
    context "with a #{kind}" do
      let(:location) { public_send(kind) }

      it 'publishes Markdown and omits empty descriptions without falling back to private text' do
        get polymorphic_path(location)
        expect(response.parsed_body.at_css('.location-description h2').text).to eq('Welcome')
        expect(response.parsed_body.at_css('.location-description strong').text).to eq('pencils')
        expect(response.body).not_to include('Private arrival details', '$321.00', 'Booking Horizon')
        location.update!(description: '')
        get polymorphic_path(location)
        expect(response.parsed_body.at_css('.location-description')).to be_nil
        expect(response.body).not_to include('Private arrival details')
      end

      it 'saves and audits descriptions through the existing scoped management endpoint' do
        grant_venue_access(venue, coordinator)
        sign_in(coordinator)
        patch polymorphic_path(location), params: { kind => { description: 'Updated **description**' } }
        expect(response).to redirect_to(polymorphic_path(location))
        expect(location.reload.description).to eq('Updated **description**')
        change = location.history_tracks.last
        expect(change.modified).to include('description' => 'Updated **description**')
        expect(change.modifier_id).to eq(coordinator.id)
      end

      it 'rejects oversize descriptions without changing stored content and accepts clearing them' do
        grant_venue_access(venue, coordinator)
        sign_in(coordinator)
        patch polymorphic_path(location), params: { kind => { description: 'x' * 5001 } }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include('Description is too long')
        expect(location.reload.description).to eq(description)
        patch polymorphic_path(location), params: { kind => { description: '' } }
        expect(response).to redirect_to(polymorphic_path(location))
        expect(location.reload.description).to eq('')
      end
    end
  end

  it 'shows application instructions instead of the description throughout preparation and application editing' do
    program.update!(application_instructions: "## How to Apply\n\nInclude **two poses**.")
    get new_program_application_registration_path(program)
    expect(response.parsed_body.at_css('.application-instructions h2').text).to eq('How to Apply')
    expect(response.parsed_body.at_css('.application-instructions strong').text).to eq('two poses')
    expect(response.parsed_body.at_css('.location-description')).to be_nil
    expect(response.body).not_to include(program.instructions, '$321.00', 'Booking Horizon')
    sign_in(create_user(email_verified_at: Time.current))
    get new_program_participation_application_path(program)
    expect(response.parsed_body.at_css('.application-instructions strong').text).to eq('two poses')
    expect(response.parsed_body.at_css('.location-description')).to be_nil
    expect(response.body).not_to include(program.instructions, '$321.00', 'Booking Horizon')
    expect(response.parsed_body.at_css('#application-editor')).to be_present
  end

  it 'omits blank application instructions without falling back to the description or private instructions' do
    get new_program_application_registration_path(program)
    expect(response.parsed_body.at_css('.application-instructions, .location-description')).to be_nil
    expect(response.body).not_to include('pencils', program.instructions)
    sign_in(create_user(email_verified_at: Time.current))
    get new_program_participation_application_path(program)
    expect(response.parsed_body.at_css('.application-instructions, .location-description')).to be_nil
    expect(response.body).not_to include('pencils', program.instructions)
  end

  it 'saves, audits, and limits application instructions through program settings' do
    grant_coordinator_access(program, coordinator)
    sign_in(coordinator)
    get edit_program_path(program)
    expect(response.parsed_body.at_css('#program_application_instructions')).to be_present
    expect(response.body).to include('before email verification')
    patch program_path(program), params: { program: { application_instructions: 'Send **references**.' } }
    expect(response).to redirect_to(program_path(program))
    expect(program.reload.application_instructions).to eq('Send **references**.')
    change = program.history_tracks.last
    expect(change.modified).to include('application_instructions' => 'Send **references**.')
    patch program_path(program), params: { program: { application_instructions: 'x' * 5001 } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Application instructions is too long')
    expect(program.reload.application_instructions).to eq('Send **references**.')
  end

  it 'keeps pay and instructions member-only and booking horizon exclusively in settings' do
    grant_coordinator_access(program, coordinator)
    sign_in(coordinator)
    get program_path(program)
    expect(response.body).to include('Private arrival details', '$321.00')
    expect(response.body).not_to include('Booking Horizon')
    get edit_program_path(program)
    expect(response.parsed_body.at_css('#program_booking_horizon_months')['value']).to eq('9')
  end
end
