# frozen_string_literal: true

require 'rails_helper'
require 'vips'

RSpec.describe 'Program photos', :aggregate_failures, :database, type: :request do
  let(:program) { create_program }
  let(:coordinator) { create_user }
  let(:uploads) { [] }
  let(:photo) { ProgramPhoto.add(program, photo_upload) }

  before { grant_coordinator_access(program, coordinator) }
  after { uploads.each(&:close!) }

  def photo_upload(bytes = Vips::Image.black(600, 900).new_from_image([140, 90, 70]).write_to_buffer('.png'))
    file = Tempfile.new(['program-photo', '.png'])
    file.binmode.write(bytes)
    file.flush
    upload = Rack::Test::UploadedFile.new(file.path, 'image/png')
    uploads.push(file, upload.tempfile)
    upload
  end

  def stored_files
    ProgramPhoto.storage.file_model.where('metadata.program_id' => program.id)
  end

  it 'previews the program photo series, falling back to venue photos and then a placeholder' do
    get programs_venue_path(program.venue)
    portrait = response.parsed_body.at_css('.program-card .location-card-photo')
    expect(portrait['href']).to eq(program_path(program))
    expect(portrait.at_css('img')['src']).to include('program-placeholder')
    expect(portrait.at_css('img')['alt']).to eq("No photo for #{program.name}")
    venue_photo = VenuePhoto.add(program.venue, photo_upload)
    get programs_venue_path(program.venue)
    expect(response.parsed_body.at_css('.program-card img')['src'])
      .to eq(venue_photo_path(program.venue, venue_photo, thumbnail: 1))
    photo
    second = ProgramPhoto.add(program, photo_upload)
    get programs_venue_path(program.venue)
    expect(response.parsed_body.at_css('.program-card img')['src'])
      .to eq(program_photo_path(program, photo, thumbnail: 1))
    expect(response.parsed_body.css('.program-card [data-photo-series] [data-photo-preview]').pluck('href'))
      .to eq([program_photo_path(program, photo), program_photo_path(program, second)])
  end

  it 'groups program information and scoped configuration without exposing parent management' do
    sign_in(coordinator)
    get edit_program_path(program)
    groups = response.parsed_body.css('.program-tabs .page-tab-group')
    expect(groups.map { |group| group.css('a').map(&:text) })
      .to eq([%w[Program Calendar Photos Participants Settings]])
    expect(response.parsed_body.css('.program-secondary-tabs a').map(&:text))
      .to eq(['Details', 'Notifications', 'Google Calendar'])
    expect(response.parsed_body.at_css('.program-tabs .tab-separator')).to be_nil
    expect(response.parsed_body.at_css('.breadcrumbs [aria-current="page"]').text).to eq('Details')
    delete session_path
    get program_path(program)
    expect(response.parsed_body.at_css('.program-tabs')).to be_nil
  end

  it 'lets program coordinators upload a separate public gallery with primary-photo controls' do
    sign_in(coordinator)
    post program_photos_path(program), params: { program_photo: { file: photo_upload } }
    expect(response).to redirect_to(photos_program_path(program))
    expect(program.reload.photos.count).to eq(1)
    expect(program.venue.photos).to be_empty
    get photos_program_path(program)
    expect(response.parsed_body.at_css('.program-tabs [aria-current="page"]').text).to eq('Photos')
    expect(response.parsed_body.at_css('.program-photo figcaption').text).to include('Public', 'Primary')
    expect(response.body).to include('Upload Photo', 'Delete Photo')
    delete session_path
    get photos_program_path(program)
    expect(response.parsed_body.at_css('.program-photo img')).to be_present
    expect(response.body).not_to include('Upload Photo', 'Delete Photo', coordinator.email)
  end

  def expect_guest_cannot_view_private_photo(second)
    delete session_path
    get photos_program_path(program)
    expect(response.parsed_body.css('[data-photo]').pluck('data-photo')).to eq([second.id.to_s])
    expect_private_photo_not_found
  end

  def expect_private_photo_not_found
    get program_photo_path(program, photo)
    expect(response).to have_http_status(:not_found)
  end

  def expect_primary_photo_changes
    patch program_photo_path(program, photo), params: { program_photo: { primary: '1' } }
    expect(photo.reload).to be_public
    expect(program.reload.primary_photo).to eq(photo)
    clear_primary_photo
  end

  def clear_primary_photo
    patch program_photo_path(program, photo), params: { program_photo: { public: '0' } }
    expect(program.reload.primary_photo_id).to be_nil
  end

  it 'lets program managers keep photos private from guests, cards, and the primary selection' do
    photo
    second = ProgramPhoto.add(program, photo_upload)
    sign_in(coordinator)
    patch program_photo_path(program, photo), params: { program_photo: { public: '0' } }
    expect(response).to redirect_to(photos_program_path(program))
    expect(photo.reload).not_to be_public
    expect(program.reload.primary_photo).to eq(second)
    get photos_program_path(program)
    expect(response.parsed_body.at_css("[data-photo='#{photo.id}'] figcaption").text).to include('Private')
    expect(response.parsed_body.at_css("[data-photo='#{photo.id}']").text).to include('Make Public')
    get programs_venue_path(program.venue)
    expect(response.parsed_body.at_css("img[src='#{program_photo_path(program, second, thumbnail: 1)}']")).to be_present
    expect_guest_cannot_view_private_photo(second)
    sign_in(coordinator)
    expect_primary_photo_changes
    patch program_photo_path(program, photo), params: { program_photo: { public: 'maybe' } }
    expect(response).to have_http_status(:bad_request)
  end

  it 'serves public optimized full images and square thumbnails with private cache validation' do
    get program_photo_path(program, photo)
    expect(response.media_type).to eq('image/webp')
    expect(response.headers['Cache-Control']).to eq('max-age=0, private, must-revalidate')
    full = Vips::Image.new_from_buffer(response.body, '')
    expect([full.width, full.height]).to eq([600, 900])
    get program_photo_path(program, photo, thumbnail: 1)
    square = Vips::Image.new_from_buffer(response.body, '')
    expect([square.width, square.height]).to eq([400, 400])
  end

  it 'audits primary selection and shows the chosen image on program and venue program cards' do
    photo
    second = ProgramPhoto.add(program, photo_upload)
    sign_in(coordinator)
    patch program_photo_path(program, second), params: { program_photo: { primary: '1' } }
    expect(response).to redirect_to(photos_program_path(program))
    expect(program.reload.primary_photo).to eq(second)
    change = program.history_tracks.last
    expect(change.modified['primary_photo_id']).to eq(second.id)
    expect(change.modifier_id).to eq(coordinator.id)
    [photos_program_path(program), programs_venue_path(program.venue)].each do |path|
      get path
      expect(response.parsed_body.at_css("img[src='#{program_photo_path(program, second, thumbnail: 1)}']"))
        .to be_present
    end
  end

  it 'keeps the venue photo separate from the optional next-session program photo' do
    venue_photo = VenuePhoto.add(program.venue, photo_upload)
    get program_path(program)
    expect(response.parsed_body.css('.next-session img, .next-session [data-photo-preview]')).to be_empty
    expect(response.parsed_body.at_css('.next-session + .venue-card img')['src'])
      .to eq(venue_photo_path(program.venue, venue_photo, thumbnail: 1))
    photo
    second = ProgramPhoto.add(program, photo_upload)
    get program_path(program)
    expect(response.parsed_body.at_css('.next-session img')['src'])
      .to eq(program_photo_path(program, photo, thumbnail: 1))
    expect(response.parsed_body.css('.next-session [data-photo-series] [data-photo-preview]').pluck('href'))
      .to eq([program_photo_path(program, photo), program_photo_path(program, second)])
    expect(response.parsed_body.at_css('.next-session + .venue-card img')['src'])
      .to eq(venue_photo_path(program.venue, venue_photo, thumbnail: 1))
  end

  it 'requires authentication and program management for writes without granting venue editing' do
    post program_photos_path(program), params: { program_photo: { file: photo_upload } }
    expect(response).to redirect_to(new_session_path)
    participant = create_user
    grant_participant_access(program, participant)
    sign_in(participant)
    patch program_photo_path(program, photo)
    expect(response).to have_http_status(:forbidden)
    delete program_photo_path(program, photo)
    expect(response).to have_http_status(:forbidden)
    sign_in(coordinator)
    post venue_photos_path(program.venue), params: { venue_photo: { file: photo_upload } }
    expect(response).to have_http_status(:forbidden)
    expect(program.reload.primary_photo_id).to be_nil
  end

  it 'scopes photo IDs to their program and keeps venue photos independent' do
    foreign = create_program
    photo
    sign_in(create_user(roles: ['system_admin']))
    [program_photo_path(foreign, photo),
     program_photo_path(program, VenuePhoto.add(program.venue, photo_upload))].each do |url|
      get url
      expect(response).to have_http_status(:not_found)
      patch url
      expect(response).to have_http_status(:not_found)
      delete url
      expect(response).to have_http_status(:not_found)
    end
    expect(program.photos.count).to eq(1)
  end

  it 'preserves all concurrent uploads past ten while program settings change' do
    11.times { ProgramPhoto.add(program, photo_upload) }
    files = Array.new(2) { photo_upload }
    files.map { |file| Thread.new { ProgramPhoto.add(Program.find(program.id), file) } }.each(&:value)
    ProgramSettingsUpdate.new(program: program, user: coordinator).call(name: 'Updated program')
    expect(program.reload.photos.count).to eq(13)
    expect(stored_files.count).to eq(26)
  end

  it 'deletes both image variants and falls back after primary deletion' do
    photo
    second = ProgramPhoto.add(program, photo_upload)
    program.update!(primary_photo_id: second.id)
    sign_in(coordinator)
    delete program_photo_path(program, second)
    expect(response).to redirect_to(photos_program_path(program))
    expect(program.reload.primary_photo).to eq(photo)
    expect(stored_files.count).to eq(2)
    get program_photo_path(program, second)
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects invalid uploads and cleans up files when photo metadata cannot be saved' do
    sign_in(coordinator)
    post program_photos_path(program), params: { program_photo: { file: photo_upload('not an image') } }
    expect(response).to redirect_to(photos_program_path(program))
    expect(stored_files.count).to eq(0)
    saved = ProgramPhoto.new(program: program)
    allow(ProgramPhoto).to receive(:new).and_return(saved)
    allow(saved).to receive(:save!).and_raise(Mongo::Error, 'Private storage failure')
    allow(NewRelic::Agent).to receive(:notice_error)
    post program_photos_path(program), params: { program_photo: { file: photo_upload } }
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).not_to include('Private storage failure')
    expect(stored_files.count).to eq(0)
  end
end
