# frozen_string_literal: true

require 'rails_helper'
require 'vips'

RSpec.describe 'Photo actions', :aggregate_failures, :database, type: :system do
  let(:participant) { create_user(name: 'Photo Participant') }
  let(:files) { [] }

  after { files.each(&:close!) }

  def image_file
    file = Tempfile.new(['photo', '.png'])
    file.binmode.write(Vips::Image.black(600, 900).new_from_image([170, 100, 70]).write_to_buffer('.png'))
    file.flush
    files << file
    file.path
  end

  def figure(photo)
    find("[data-photo='#{photo.id}']")
  end

  def upload_profile_photo
    attach_file 'New Photo', image_file
    click_on 'Upload Photo'
    expect(page).to have_css('.profile-photo', count: 2)
    expect(page).to have_css('.flash', count: 1)
    participant.reload.profile_photos.last
  end

  it 'uploads, toggles visibility, and sets the primary profile photo without reloading the page' do
    first = ProfilePhoto.add(participant, Rack::Test::UploadedFile.new(image_file, 'image/png'))
    sign_in_through_browser(participant)
    visit photos_profile_path
    mark_page
    second = upload_profile_photo

    figure(first).click_on('Make Private')
    expect(figure(first)).to have_css('.status-label-private', text: 'Private').and have_button('Make Public')
    expect(participant.reload.profile_photos.find(first.id)).not_to be_public
    expect(figure(second)).to have_css('.status-label', text: 'Primary')

    figure(first).click_on('Make Primary')
    expect(figure(first)).to have_css('.status-label', text: 'Primary')
    expect(figure(first)).to have_css('.status-label-success', text: 'Public')
    expect(participant.reload.primary_profile_photo.id).to eq(first.id)

    figure(second).click_on('Delete Photo')
    expect(page).to have_css('.profile-photo', count: 1)
    expect(participant.reload.profile_photos.map(&:id)).to eq([first.id])
    expect_unchanged_page
  end

  it 'uploads and sets the primary venue photo without reloading the page' do
    admin = create_user(roles: ['system_admin'])
    venue = create_venue
    sign_in_through_browser(admin)
    visit photos_venue_path(venue)
    mark_page

    2.times do |index|
      attach_file 'New Photo', image_file
      click_on 'Upload Photo'
      expect(page).to have_css('.venue-photo', count: index + 1)
    end
    second = venue.reload.photos.order_by(created_at: :asc).last

    figure(second).click_on('Make Primary')
    expect(figure(second)).to have_css('.status-label', text: 'Primary')
    expect(venue.reload.primary_photo.id).to eq(second.id)
    expect_unchanged_page
  end

  it 'uploads dropped photos one at a time without reloading the page' do
    sign_in_through_browser(participant)
    visit photos_profile_path
    mark_page
    expect(drop_files(image_file, %w[one.png two.png notes.txt])).to be(true)
    expect(page).to have_css('.profile-photo', count: 2)
    expect(page).to have_no_css('.photo-drop-target')
    expect(participant.reload.profile_photos.size).to eq(2)
    expect_unchanged_page
  end

  it 'reloads the page without JavaScript' do
    ProfilePhoto.add(participant, Rack::Test::UploadedFile.new(image_file, 'image/png'))
    without_javascript do
      sign_in_through_browser(participant)
      visit photos_profile_path
      click_on 'Make Private'
      expect(page).to have_button('Make Public')
    end
  end
end
