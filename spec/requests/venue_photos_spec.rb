# frozen_string_literal: true

require 'rails_helper'
require 'vips'

RSpec.describe 'Venue photos', :aggregate_failures, :database, type: :request do
  let(:venue) { create_venue }
  let(:admin) { create_user(roles: ['system_admin']) }
  let(:uploads) { [] }
  let(:photo) { VenuePhoto.add(venue, photo_upload) }

  before { admin }
  after { uploads.each(&:close!) }

  def raw_upload(bytes)
    file = Tempfile.new(['venue-photo', '.png'])
    file.binmode.write(bytes)
    file.flush
    upload = Rack::Test::UploadedFile.new(file.path, 'image/png')
    uploads.push(file, upload.tempfile)
    upload
  end

  def photo_upload
    image = Vips::Image.black(600, 900).new_from_image([120, 150, 90])
    raw_upload(image.write_to_buffer('.png'))
  end

  def stored_files
    VenuePhoto.storage.file_model.where('metadata.venue_id' => venue.id)
  end

  it 'keeps a linked placeholder on venue cards without photos, including after the last photo is deleted' do
    sign_in(admin)
    selector = ".venue-card .location-card-photo[href='#{venue_path(venue)}']"
    get venues_path
    portrait = response.parsed_body.at_css(selector)
    expect(portrait['href']).to eq(venue_path(venue))
    expect(portrait.at_css('img')['src']).to include('venue-placeholder')
    expect(portrait.at_css('img')['alt']).to eq("No photo for #{venue.name}")
    photo.destroy!
    get venues_path
    expect(response.parsed_body.at_css("#{selector} img")['src']).to include('venue-placeholder')
    get photos_venue_path(venue)
    expect(response.parsed_body.css('.venue-photo')).to be_empty
    expect(response.body).to include('No venue photos yet.')
  end

  it 'shows venue placeholders in home and profile booking lists but not program-only booking cards' do
    participant = create_user
    program = create_program(venue: venue)
    grant_participant_access(program, participant)
    date = (Date.current..(Date.current + 7)).find { |day| day.cwday == 1 && day > Date.current }
    track_booking(BookingMutation.new(program: program, user: participant).book(date: date.iso8601))
    sign_in(participant)
    get bookings_profile_path
    portrait = response.parsed_body.at_css('.upcoming-booking-photo')
    expect(portrait.at_css('img')['src']).to include('venue-placeholder')
    expect(portrait.at_css('a')['href']).to eq(venue_path(venue))
    expect(portrait.at_css('[data-photo-preview]')).to be_nil
    get calendar_program_path(program)
    expect(response.parsed_body.at_css('.upcoming-booking-photo')).to be_nil
  end

  it 'keeps the photo-led venue directory separate from public per-venue program tabs' do
    photo
    program = create_program(venue: venue, instructions: 'Private instructions')
    sign_in(admin)
    get venues_path
    expect(response.parsed_body.at_css(".venue-card img[src='#{venue_photo_path(venue, photo, thumbnail: 1)}']"))
      .to be_present
    expect(response.parsed_body.at_css('.venue-card').text).to include(venue.address)
    expect(response.body).not_to include(program.name, 'Private instructions')
    expect(response.parsed_body.css('.directory-tabs a').map(&:text)).not_to include('Programs')
    delete session_path
    get programs_venue_path(venue)
    expect(response.parsed_body.css('.venue-card')).to be_empty
    expect(response.parsed_body.at_css('.program-card').text).to include(program.name, venue.address)
    expect(response.body).not_to include('Private instructions')
  end

  it 'shows only the programs empty state when a venue has no programs' do
    get programs_venue_path(venue)
    expect(response.body).to include('No programs yet.')
    expect(response.parsed_body.css('.venue-card, .program-card')).to be_empty
  end

  it 'lets admins upload public venue photos and shows square thumbnails without guest edit controls' do
    sign_in(admin)
    post venue_photos_path(venue), params: { venue_photo: { file: photo_upload } }
    expect(response).to redirect_to(photos_venue_path(venue))
    expect(venue.photos.count).to eq(1)
    get photos_venue_path(venue)
    expect(response.parsed_body.at_css('.venue-tabs [aria-current="page"]').text).to eq('Photos')
    expect(response.parsed_body.css('.venue-card')).to be_empty
    expect(response.parsed_body.css('.venue-photo button.secondary-action').map(&:text)).to eq(['Make Private',
                                                                                                'Delete Photo'])
    delete session_path
    get photos_venue_path(venue)
    image = response.parsed_body.at_css('.venue-photo img')
    expect(image.attributes.transform_values(&:value)).to include('width' => '400', 'height' => '400')
    expect(response.body).not_to include('Upload Photo', admin.email)
    expect(response.parsed_body.at_css('.venue-photo button.secondary-action')).to be_nil
    expect(image.parent['data-photo-preview']).to eq('true')
    expect(image.parent['target']).to be_nil
  end

  it 'keeps venue photos on a public page without granting management access' do
    get venue_path(venue)
    expect(response.parsed_body.at_css('.venue-tabs, .photo-gallery')).to be_nil
    get photos_venue_path(venue)
    expect(response.body).to include('No venue photos yet.')
    expect(response.parsed_body.at_css('.breadcrumbs [aria-current="page"]').text).to eq('Photos')
    expect(response.parsed_body.css('main form')).to be_empty
    sign_in(admin)
    get edit_venue_path(venue)
    expect(response.parsed_body.css('.venue-tabs a').map(&:text))
      .to eq(%w[Venue Programs Photos Settings])
    expect(response.parsed_body.at_css('.venue-tabs [aria-current="page"]').text).to eq('Settings')
    expect(response.parsed_body.css('.venue-secondary-tabs a').map(&:text)).to eq(%w[Details Coordinators Security])
  end

  it 'groups programs and photos with management while keeping write actions private' do
    sign_in(admin)
    get venues_path
    expect(response.parsed_body.css('.directory-tabs .page-tab-group').map { |group| group.css('a').map(&:text) })
      .to eq([['Venues'], ['Create Venue']])
    get edit_venue_path(venue)
    expect(response.parsed_body.css('.venue-tabs .page-tab-group').map { |group| group.css('a').map(&:text) })
      .to eq([%w[Venue Programs Photos Settings]])
    expect(response.parsed_body.at_css('.venue-tabs [aria-current="page"]').text).to eq('Settings')
    expect(response.parsed_body.at_css('.venue-secondary-tabs [aria-current="page"]').text).to eq('Details')
    get programs_venue_path(venue)
    expect(response.parsed_body.at_css('main > p:last-child a.button-link')['href'])
      .to eq(new_venue_program_path(venue))
    get venue_coordinators_path(venue)
    expect(response.parsed_body.at_css('main > p:last-child a')['href']).to eq(new_venue_coordinator_path(venue))
    delete session_path
    get venue_path(venue)
    expect(response.parsed_body.at_css('.page-tabs')).to be_nil
  end

  it 'previews every public venue photo from the venue card' do
    photo
    second = VenuePhoto.add(venue, photo_upload)
    get venues_path
    expect(response.parsed_body.css('.venue-card [data-photo-series] [data-photo-preview]').pluck('href'))
      .to eq([venue_photo_path(venue, photo), venue_photo_path(venue, second)])
  end

  it 'lists every active venue to guests' do
    venue
    hidden = create_venue(name: 'Hidden Venue', active: false)
    get venues_path
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.css('.venue-card h2 a').map(&:text)).to include(venue.name)
    expect(response.body).not_to include(hidden.name)
    expect(response.parsed_body.at_css('.page-tabs')).to be_nil
  end

  it 'serves full-size and square optimized WebP images publicly with private cache validation' do
    get venue_photo_path(venue, photo)
    expect(response.media_type).to eq('image/webp')
    expect(response.headers['Cache-Control']).to eq('max-age=0, private, must-revalidate')
    full = Vips::Image.new_from_buffer(response.body, '')
    expect([full.width, full.height]).to eq([600, 900])
    get venue_photo_path(venue, photo, thumbnail: 1)
    square = Vips::Image.new_from_buffer(response.body, '')
    expect([square.width, square.height]).to eq([400, 400])
  end

  it 'lets venue coordinators select an audited primary photo' do
    photo
    second = VenuePhoto.add(venue, photo_upload)
    coordinator = create_user
    grant_venue_access(venue, coordinator)
    sign_in(coordinator)
    get photos_venue_path(venue)
    expect(response.parsed_body.at_css("[data-photo='#{photo.id}'] figcaption").text).to include('Primary')
    patch venue_photo_path(venue, second), params: { venue_photo: { primary: '1' } }
    expect(response).to redirect_to(photos_venue_path(venue))
    expect(venue.reload.primary_photo).to eq(second)
    change = HistoryTracker.where('association_chain.id': venue.id, action: 'update').last
    expect(change.modified['primary_photo_id']).to eq(second.id)
    expect(change.modifier_id).to eq(coordinator.id)
    get photos_venue_path(venue)
    selected = response.parsed_body.at_css("[data-photo='#{second.id}']")
    expect(selected.at_css('figcaption').text).to include('Primary')
    expect(selected.text).not_to include('Make Primary')
  end

  it 'shows the Details section without exposing admin settings to venue coordinators' do
    coordinator = create_user
    grant_venue_access(venue, coordinator)
    sign_in(coordinator)
    get edit_venue_path(venue)
    expect(response.parsed_body.at_css('.venue-tabs [aria-current="page"]').text).to eq('Settings')
    expect(response.parsed_body.css('.venue-secondary-tabs a').map(&:text)).to eq(['Details'])
  end

  def expect_guest_cannot_view_private_photo(second)
    delete session_path
    get photos_venue_path(venue)
    expect(response.parsed_body.css('[data-photo]').pluck('data-photo')).to eq([second.id.to_s])
    expect_private_photo_not_found
  end

  def expect_private_photo_not_found
    get venue_photo_path(venue, photo)
    expect(response).to have_http_status(:not_found)
  end

  def expect_primary_photo_changes
    patch venue_photo_path(venue, photo), params: { venue_photo: { primary: '1' } }
    expect(photo.reload).to be_public
    expect(venue.reload.primary_photo).to eq(photo)
    clear_primary_photo
  end

  def clear_primary_photo
    patch venue_photo_path(venue, photo), params: { venue_photo: { public: '0' } }
    expect(venue.reload.primary_photo_id).to be_nil
  end

  it 'lets coordinators keep venue photos private from guests, cards, and the primary selection' do
    photo
    second = VenuePhoto.add(venue, photo_upload)
    sign_in(admin)
    patch venue_photo_path(venue, photo), params: { venue_photo: { public: '0' } }
    expect(response).to redirect_to(photos_venue_path(venue))
    expect(photo.reload).not_to be_public
    expect(venue.reload.primary_photo).to eq(second)
    get photos_venue_path(venue)
    labels = response.parsed_body.at_css("[data-photo='#{photo.id}'] figcaption").text
    expect(labels).to include('Private')
    expect(response.parsed_body.at_css("[data-photo='#{photo.id}']").text).to include('Make Public')
    get venues_path
    expect(response.parsed_body.at_css('.venue-card img')['src']).to eq(venue_photo_path(venue, second, thumbnail: 1))
    expect_guest_cannot_view_private_photo(second)
    sign_in(admin)
    expect_primary_photo_changes
  end

  it 'falls back to the first remaining photo after deleting the primary photo without guest edit controls' do
    photo
    second = VenuePhoto.add(venue, photo_upload)
    venue.update!(primary_photo_id: second.id)
    sign_in(admin)
    delete venue_photo_path(venue, second)
    expect(venue.reload.primary_photo).to eq(photo)
    delete session_path
    get photos_venue_path(venue)
    expect(response.body).not_to include('Make Primary', 'Delete Photo')
    expect(venue.photos.count).to eq(1)
  end

  it 'shows the selected public venue photo inside the homepage booking card' do
    photo
    second = VenuePhoto.add(venue, photo_upload)
    venue.update!(primary_photo_id: second.id)
    participant = create_user
    program = create_program(venue: venue)
    grant_participant_access(program, participant)
    date = (Date.current..(Date.current + 7)).find { |day| day.cwday == 1 && day > Date.current }
    track_booking(BookingMutation.new(program: program, user: participant).book(date: date.iso8601))
    sign_in(participant)
    get bookings_profile_path
    card = response.parsed_body.at_css('.upcoming-booking')
    expect(card.at_css('.upcoming-booking-photo img')['src']).to eq(venue_photo_path(venue, second, thumbnail: 1))
    expect(card.at_css('.upcoming-booking-photo a')['href']).to eq(venue_photo_path(venue, second))
    sign_in(admin)
    patch venue_photo_path(create_venue, second), params: { venue_photo: { primary: '1' } }
    expect(response).to have_http_status(:not_found)
    expect(venue.reload.primary_photo).to eq(second)
  end

  it 'has no ten-photo cap and retains simultaneous uploads alongside venue settings edits' do
    11.times { VenuePhoto.add(venue, photo_upload) }
    owners = Array.new(2) { Venue.find(venue.id) }
    files = Array.new(2) { photo_upload }
    owners.zip(files).map { |owner, file| Thread.new { VenuePhoto.add(owner, file) } }.each(&:value)
    venue.update!(instagram_handle: '@venue.account')
    expect(venue.photos.count).to eq(13)
    expect(stored_files.count).to eq(26)
    get photos_venue_path(venue)
    expect(response.parsed_body.css('.venue-photo').count).to eq(13)
  end

  it 'requires authentication and does not grant photo writes to participants or schedule organizers' do
    url = venue_photo_path(venue, photo)
    post venue_photos_path(venue), params: { venue_photo: { file: photo_upload } }
    expect(response).to redirect_to(new_session_path)
    user = create_user
    program = create_program(venue: venue)
    grant_coordinator_access(program, user)
    grant_participant_access(program, user)
    sign_in(user)
    post venue_photos_path(venue), params: { venue_photo: { file: photo_upload } }
    expect(response).to have_http_status(:forbidden)
    delete url
    expect(response).to have_http_status(:forbidden)
    patch url
    expect(response).to have_http_status(:forbidden)
    expect(venue.reload.primary_photo_id).to be_nil
    expect(venue.photos.count).to eq(1)
  end

  it 'scopes both public reads and admin deletion to the requested venue' do
    foreign = create_venue
    photo
    get venue_photo_path(foreign, photo)
    expect(response).to have_http_status(:not_found)
    sign_in(admin)
    delete venue_photo_path(foreign, photo)
    expect(response).to have_http_status(:not_found)
    expect(venue.photos.count).to eq(1)
    private_photo = ProfilePhoto.add(create_user, photo_upload)
    get venue_photo_path(venue, private_photo.id)
    expect(response).to have_http_status(:not_found)
  end

  it 'deletes both GridFS variants and denies deleted image URLs' do
    sign_in(admin)
    url = venue_photo_path(venue, photo)
    ids = [photo.image_id, photo.thumbnail_id]
    delete url
    expect(response).to redirect_to(photos_venue_path(venue))
    expect(venue.reload.photos).to be_empty
    expect(stored_files.count).to eq(0)
    expect(VenuePhoto.storage.chunk_model.where(:files_id.in => ids).count).to eq(0)
    get url
    expect(response).to have_http_status(:not_found)
  end

  it 'removes venue photo metadata and files when their venue is destroyed' do
    photo
    venue.destroy!
    expect(VenuePhoto.where(venue_id: venue.id)).to be_empty
    expect(stored_files.count).to eq(0)
  end

  it 'rejects corrupt, unsupported, and oversize uploads without storing files' do
    sign_in(admin)
    ['', 'not an image', '<svg/>', 'x' * 10_485_761].each do |bytes|
      post venue_photos_path(venue), params: { venue_photo: { file: raw_upload(bytes) } }
      expect(response).to have_http_status(:see_other)
      expect(venue.photos).to be_empty
      expect(stored_files.count).to eq(0)
    end
  end

  it 'cleans up stored images when standalone photo metadata cannot be saved' do
    saved = VenuePhoto.new(venue: venue)
    allow(VenuePhoto).to receive(:new).and_return(saved)
    allow(saved).to receive(:save!).and_raise(Mongo::Error, 'Metadata write failed')
    expect { VenuePhoto.add(venue, photo_upload) }.to raise_error(Mongo::Error)
    expect(stored_files.count).to eq(0)
    expect(venue.reload.photos).to be_empty
  end

  it 'reports storage errors without exposing details or claiming upload success' do
    sign_in(admin)
    error = Mongo::Error.new('Private storage details')
    allow(VenuePhoto).to receive(:add).and_raise(error)
    allow(NewRelic::Agent).to receive(:notice_error)
    post venue_photos_path(venue), params: { venue_photo: { file: photo_upload } }
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).not_to include(error.message)
    expect(NewRelic::Agent).to have_received(:notice_error).with(error).once
  end
end
