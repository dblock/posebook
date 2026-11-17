# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Edit in place', :aggregate_failures, :database, type: :system do
  let(:user) { create_user(name: 'Riley Model') }

  it 'saves the profile and shows validation errors without leaving the edit page' do
    sign_in_through_browser(user)
    visit edit_profile_path
    expect(page).to have_field('Phone', with: '+1 (202) 555-0101')
    mark_page

    fill_in 'Name', with: 'Riley Saved'
    click_on 'Save Profile'
    expect(page).to have_css('.flash', text: 'Profile saved.')
    expect(page).to have_current_path(edit_profile_path)
    expect(page).to have_field('Name', with: 'Riley Saved')
    expect(user.reload.name).to eq('Riley Saved')

    fill_in 'Email', with: 'changed@example.test'
    click_on 'Save Profile'
    expect(page).to have_css('.flash-alert', text: 'Current Password')
    expect(page).to have_current_path(edit_profile_path)

    check 'Share my Instagram publicly and tag me'
    expect(find_field('Instagram Handle')[:required]).to be(true)
    expect_unchanged_page
  end

  it 'saves a venue without leaving the edit page' do
    admin = create_user(roles: ['system_admin'])
    venue = create_venue(name: 'Old Studio')
    sign_in_through_browser(admin)
    visit edit_venue_path(venue)
    mark_page

    fill_in 'Name', with: 'New Studio'
    click_on 'Save Venue'
    expect(page).to have_css('.flash', text: 'Venue')
    expect(page).to have_field('Name', with: 'New Studio')
    expect(page).to have_current_path(edit_venue_path(venue))
    expect(venue.reload.name).to eq('New Studio')
    expect_unchanged_page
  end

  it 'saves another user as an admin without leaving the edit page' do
    sign_in_through_browser(create_user(roles: ['system_admin']))
    visit edit_admin_user_path(user)
    expect(page).to have_field('Phone', with: '+1 (202) 555-0101')
    mark_page

    fill_in 'Name', with: 'Riley Admin Edit'
    click_on 'Save User'
    expect(page).to have_css('.flash', text: 'User information saved.')
    expect(page).to have_current_path(edit_admin_user_path(user))
    expect(page).to have_button('Save User', disabled: false)
    expect(user.reload.name).to eq('Riley Admin Edit')
    expect_unchanged_page
  end

  it 'still leaves the page after self-deactivation' do
    sign_in_through_browser(user)
    visit security_profile_path
    within('#deactivate-account') do
      fill_in 'Current Password', with: DatabaseHelpers::TEST_PASSWORD
      click_on 'Deactivate My Account'
    end
    expect(page).to have_current_path(new_session_path)
    expect(page).to have_css('.flash', text: 'Your account has been deactivated.')
  end
end
