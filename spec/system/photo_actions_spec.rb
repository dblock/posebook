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

  def expect_card_series(path, selector, sources, viewport = :desktop)
    visit path
    find("#{selector} [data-photo-preview]", visible: true).click
    dialog = find('[data-photo-dialog]')
    expect_preview_photo(dialog, sources.first, '1 of 2')
    dialog.find('[data-photo-next]').click
    expect_preview_photo(dialog, sources.last, '2 of 2')
    expect_no_horizontal_overflow
    capture_screenshot("card-preview-#{selector.delete('.')}-#{viewport}")
    dialog.send_keys(:escape)
  end

  def expect_preview_photo(dialog, source, position)
    expect(dialog).to have_css("img[src$='#{source}']").and have_text(position)
  end

  def card_photos(owner)
    type = owner.is_a?(Venue) ? VenuePhoto : ProgramPhoto
    first, primary, private_photo = Array.new(3) do
      type.add(owner, Rack::Test::UploadedFile.new(image_file, 'image/png'))
    end
    private_photo.update!(public: false)
    owner.update!(primary_photo_id: primary.id)
    [primary, first].map do |photo|
      owner.is_a?(Venue) ? venue_photo_path(owner, photo) : program_photo_path(owner, photo)
    end
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

  it 'steps through the photo gallery from the preview popup' do
    venue = create_venue
    photos = Array.new(3) { VenuePhoto.add(venue, Rack::Test::UploadedFile.new(image_file, 'image/png')) }
    visit photos_venue_path(venue)
    sources = photos.map { |photo| venue_photo_path(venue, photo) }
    figure(photos.first).find('[data-photo-preview]').click
    dialog = find('[data-photo-dialog]')
    expect(dialog).to have_css("img[src$='#{sources[0]}']").and have_text('1 of 3')
    dialog.find('[data-photo-next]').click
    expect(dialog).to have_css("img[src$='#{sources[1]}']").and have_text('2 of 3')
    dialog.send_keys(:right)
    expect(dialog).to have_css("img[src$='#{sources[2]}']")
    dialog.send_keys(:right)
    expect(dialog).to have_css("img[src$='#{sources[0]}']")
    dialog.find('[data-photo-previous]').click
    expect(dialog).to have_css("img[src$='#{sources[2]}']").and have_text('3 of 3')
  end

  it 'navigates only public photos from venue, program, and next session cards at every viewport' do
    program = create_program
    venue_sources = card_photos(program.venue)
    program_sources = card_photos(program)
    each_viewport do |viewport|
      expect_card_series(venue_path(program.venue), '.venue-card', venue_sources, viewport)
      expect_card_series(venue_path(program.venue), '.program-card', program_sources, viewport)
      expect_card_series(program_path(program), '.next-session', program_sources, viewport)
    end
  end

  it 'navigates venue photos from an upcoming booking card' do
    program = create_program
    sources = card_photos(program.venue)
    grant_participant_access(program, participant)
    date = ((Date.current + 1)..(Date.current + 7)).find { |day| day.cwday == 1 }
    track_booking(BookingMutation.new(program: program, user: participant).book(date: date.iso8601))
    sign_in_through_browser(participant)
    expect_card_series(bookings_profile_path, '.upcoming-booking', sources)
  end

  it 'opens the card primary image directly without JavaScript' do
    venue = create_venue
    sources = card_photos(venue)
    without_javascript do
      visit venue_path(venue)
      find('.venue-card [data-photo-preview]', visible: true).click
      expect(page).to have_current_path(sources.first)
    end
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
