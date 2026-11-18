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

  it 'formats supported phone input only after focus leaves the field without saving' do
    sign_in_through_browser(user)
    visit edit_profile_path
    {
      '2125551234' => '+1 (212) 555-1234', '(212) 555-1234' => '+1 (212) 555-1234',
      '1.212.555.1234' => '+1 (212) 555-1234', '+1 212 555 1234' => '+1 (212) 555-1234',
      '0044 20 7946 0958' => '+442079460958', '44 20 7946 0958' => '+442079460958',
      '+39 02 1234 5678' => '+390212345678'
    }.each do |input, expected|
      fill_in 'Phone', with: input
      expect(page).to have_field('Phone', with: input)
      capture_screenshot('phone-format-before-blur') if input == '2125551234'
      find_field('Phone').send_keys(:tab)
      expect(page).to have_field('Phone', with: expected)
      capture_screenshot('phone-format-after-blur') if input == '2125551234'
    end
    expect(user.reload.phone).to eq('+12025550101')
    expect(page).to have_no_css('.flash', text: 'Profile saved.')
  end

  it 'leaves incomplete, malformed, ambiguous, and empty phone input unchanged on blur' do
    sign_in_through_browser(user)
    visit edit_profile_path
    ['', '212', '+123', '0123456789', '212+5551234', '++12125551234',
     '(212) 555-1234 ext 5', '+44 (0)20 7946 0958', '(0044) 20 7946 0958', '+1234567890123456'].each do |input|
      fill_in 'Phone', with: input
      find_field('Phone').send_keys(:tab)
      expect(page).to have_field('Phone', with: input)
    end
    expect(user.reload.phone).to eq('+12025550101')
  end

  it 'keeps phone formatting active in admin forms after an in-place save replaces the fields' do
    sign_in_through_browser(create_user(roles: ['system_admin']))
    visit edit_admin_user_path(user)
    fill_in 'Phone', with: '2125551234'
    find_field('Phone').send_keys(:tab)
    expect(page).to have_field('Phone', with: '+1 (212) 555-1234')
    expect(user.reload.phone).to eq('+12025550101')
    click_on 'Save User'
    expect(page).to have_css('.flash', text: 'User information saved.')
    fill_in 'Phone', with: '6465559876'
    find_field('Phone').send_keys(:tab)
    expect(page).to have_field('Phone', with: '+1 (646) 555-9876')
    expect(user.reload.phone).to eq('+12125551234')
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
