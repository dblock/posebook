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
end
