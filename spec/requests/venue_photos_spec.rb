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

  it 'lets admins upload public venue photos and shows square thumbnails without guest edit controls' do
    sign_in(admin)
    post venue_photos_path(venue), params: { venue_photo: { file: photo_upload } }
    expect(response).to redirect_to(venue_path(venue))
    expect(venue.photos.count).to eq(1)
    get venue_path(venue)
    expect(response.parsed_body.at_css('.venue-photo button.secondary-action').text).to eq('Delete Photo')
    delete session_path
    get venue_path(venue)
    image = response.parsed_body.at_css('.venue-photo img')
    expect(image.attributes.transform_values(&:value)).to include('width' => '400', 'height' => '400')
    expect(response.body).not_to include('Upload Venue Photo', admin.email)
    expect(response.parsed_body.at_css('.venue-photo button.secondary-action')).to be_nil
    expect(image.parent['data-photo-preview']).to eq('true')
    expect(image.parent['target']).to be_nil
  end

  it 'serves full-size and square optimized WebP images publicly without persistent caching' do
    get venue_photo_path(venue, photo)
    expect(response.media_type).to eq('image/webp')
    expect(response.headers['Cache-Control']).to include('no-store')
    full = Vips::Image.new_from_buffer(response.body, '')
    expect([full.width, full.height]).to eq([600, 900])
    get venue_photo_path(venue, photo, thumbnail: 1)
    square = Vips::Image.new_from_buffer(response.body, '')
    expect([square.width, square.height]).to eq([400, 400])
  end

  it 'has no ten-photo cap and retains simultaneous uploads alongside venue settings edits' do
    11.times { VenuePhoto.add(venue, photo_upload) }
    owners = Array.new(2) { Venue.find(venue.id) }
    files = Array.new(2) { photo_upload }
    owners.zip(files).map { |owner, file| Thread.new { VenuePhoto.add(owner, file) } }.each(&:value)
    venue.update!(instagram_handle: '@venue.account')
    expect(venue.photos.count).to eq(13)
    expect(stored_files.count).to eq(26)
    get venue_path(venue)
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
    expect(response).to redirect_to(venue_path(venue))
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
