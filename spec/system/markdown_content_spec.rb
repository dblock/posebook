# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Markdown content', :aggregate_failures, :database, type: :system do
  let(:coordinator) { create_user(name: 'Studio Coordinator') }
  let(:program) { create_program(name: 'Monday Drawing') }

  before do
    grant_coordinator_access(program, coordinator)
    sign_in_through_browser(coordinator)
  end

  it 'renders saved private instructions without JavaScript and fits every viewport' do
    visit edit_program_path(program)
    fill_in 'Instructions',
            with: "## Arrival\n\n- **Bring pencils**\n- [Directions](https://example.test)\n\n```\n#{'x' * 200}\n```"
    click_on 'Save Program'
    expect(page).to have_css('.flash', text: 'saved')
    each_viewport do |viewport|
      without_javascript do
        visit program_path(program)
        expect(page).to have_css('.markdown-content h2', text: 'Arrival')
        expect(page).to have_css('.markdown-content li strong', text: 'Bring pencils')
        expect_no_horizontal_overflow
        capture_screenshot("markdown-instructions-#{viewport}")
      end
    end
  end

  it 'edits public venue and program descriptions with visibility and formatting hints' do
    grant_venue_access(program.venue, coordinator)
    [program.venue, program].each do |location|
      visit edit_polymorphic_path(location)
      expect(page).to have_text('Public')
      expect(page).to have_text('Supports Markdown')
      fill_in 'Description', with: 'Public **drawing** sessions.'
      click_on location.is_a?(Venue) ? 'Save Venue' : 'Save Program'
      expect(page).to have_css('.flash')
      visit polymorphic_path(location)
      expect(page).to have_css('.location-description strong', text: 'drawing')
    end
  end

  def expect_public_description
    expect(page).to have_css('.location-description h2', text: 'Draw Together')
    expect(page).to have_css('.location-description strong', text: 'All Levels')
    expect(page.text).not_to include('Private arrival details', '$321.00', 'Booking Horizon')
    expect_no_horizontal_overflow
  end

  it 'shows public descriptions on venue, program, and preparation pages without JavaScript at every viewport' do
    content = "## Draw Together\n\n**All Levels** welcome.\n\n- Bring pencils\n- https://example.test/#{'a' * 150}"
    program.update!(description: content, instructions: 'Private arrival details', pay: 321,
                    applications_enabled: true)
    program.venue.update!(description: content)
    sign_out_through_browser
    each_viewport do |viewport|
      [venue_path(program.venue), program_path(program)].each do |path|
        without_javascript do
          visit path
          expect_public_description
          capture_screenshot("public-description-#{path.split('/').last}-#{viewport}")
        end
      end
    end
  end

  def expect_application_instructions
    expect(page).to have_css('.application-instructions h2', text: 'How to Apply')
    expect(page).to have_css('.application-instructions strong', text: 'two reference poses')
    expect(page.text).not_to include('Draw Together', 'Private arrival details', '$321.00')
    expect_no_horizontal_overflow
  end

  it 'shows application instructions above preparation and verified applicant editors' do
    program.update!(description: '## Draw Together', instructions: 'Private arrival details', pay: 321,
                    application_instructions: "## How to Apply\n\nShare **two reference poses**.\n\n" \
                                              "- https://example.test/#{'a' * 150}", applications_enabled: true)
    sign_out_through_browser
    each_viewport do |viewport|
      without_javascript { visit new_program_application_registration_path(program) }
      expect_application_instructions
      capture_screenshot("application-instructions-registration-#{viewport}")
    end
    sign_in_through_browser(create_user(email_verified_at: Time.current))
    each_viewport do |viewport|
      visit new_program_participation_application_path(program)
      expect_application_instructions
      expect(page).to have_button('Submit Application', disabled: true)
      capture_screenshot("application-instructions-#{viewport}")
    end
  end
end
