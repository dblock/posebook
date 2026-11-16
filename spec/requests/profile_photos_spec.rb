# frozen_string_literal: true

require 'rails_helper'
require 'vips'

RSpec.describe 'Profile photos', :aggregate_failures, :database, type: :request do
  let(:participant) { create_user(name: 'Account Participant', display_name: 'Public Participant') }
  let(:photo) { ProfilePhoto.add(participant, photo_upload) }
  let(:photo_url) { participant_photo_path(participant, photo.id) }
  let(:uploads) { [] }

  after { uploads.each(&:close!) }

  def raw_upload(bytes)
    file = Tempfile.new(['private-filename', '.jpg'])
    file.binmode.write(bytes)
    file.flush
    upload = Rack::Test::UploadedFile.new(file.path, 'image/jpeg')
    uploads.push(file, upload.tempfile)
    upload
  end

  def photo_upload(width: 600, height: 900, format: '.png', orientation: 1)
    image = Vips::Image.black(width, height).new_from_image([170, 100, 70])
    image = image.mutate do |mutable|
      mutable.set_type!(GObject::GINT_TYPE, 'orientation', orientation)
      mutable.set_type!(GObject::GSTR_TYPE, 'exif-ifd0-Artist', 'Private metadata')
    end
    raw_upload(image.write_to_buffer(format))
  end

  def organizer_for(user)
    program = create_program
    grant_participant_access(program, user)
    organizer = create_user
    grant_coordinator_access(program, organizer)
    organizer
  end

  def stored_files
    ProfilePhoto.storage.file_model.where('metadata.user_id' => participant.id)
  end

  it 'uses linked portrait placeholders for admin users without photos and keeps real photo thumbnails' do
    sign_in(create_user(roles: ['system_admin']))
    selector = ".participant-portrait[href='#{admin_user_path(participant)}']"
    get admin_users_path
    portrait = response.parsed_body.at_css(selector)
    expect(portrait.at_css('img')['src']).to include('profile-placeholder')
    expect(portrait.at_css('img')['alt']).to eq("No profile photo for #{participant.name}")
    photo
    get admin_users_path
    expect(response.parsed_body.at_css("#{selector} img")['src'])
      .to eq(participant_photo_path(participant, photo.id, thumbnail: 1))
    photo.remove(participant)
    get admin_users_path
    expect(response.parsed_body.at_css("#{selector} img")['src']).to include('profile-placeholder')
  end

  it 'uploads publicly by default and offers square linked thumbnails and per-photo controls' do
    sign_in(participant)
    post participant_photos_path(participant), params: { profile_photo: { file: photo_upload } }
    expect(response).to have_http_status(:see_other)
    expect(participant.reload.profile_photos.map(&:public?)).to eq([true])
    follow_redirect!
    image = response.parsed_body.at_css('.profile-photo img')
    expect(image.attributes.transform_values(&:value)).to include('width' => '400', 'height' => '400')
    expect(response.body).to include('Make Private', 'Delete Photo')
    expect(response.parsed_body.css('.photo-actions button.secondary-action').map(&:text))
      .to contain_exactly('Make Private', 'Delete Photo')
    expect(response.parsed_body.at_css('.profile-photo .status-label-success').text).to eq('Public')
  end

  it 'corrects orientation, strips metadata, preserves full-image proportions and creates optimized WebP squares' do
    upload = photo_upload(width: 2400, height: 1200, format: '.jpg', orientation: 6)
    saved = ProfilePhoto.add(participant, upload)
    full = Vips::Image.new_from_buffer(saved.bytes, '')
    thumbnail = Vips::Image.new_from_buffer(saved.bytes(thumbnail: true), '')
    expect([full.width, full.height]).to eq([800, 1600])
    expect([thumbnail.width, thumbnail.height]).to eq([400, 400])
    expect(full.get('vips-loader')).to eq('webpload_buffer')
    expect(full.get_typeof('exif-data')).to eq(0)
    expect(full.get_typeof('orientation')).to eq(0)
    expect(saved.bytes.bytesize).to be < upload.tempfile.size
  end

  it 'keeps private photos in the owner gallery with full-image popup links' do
    photo.change_visibility(participant, false)
    sign_in(participant)
    get photos_profile_path
    link = response.parsed_body.at_css('.profile-photo [data-photo-preview]')
    expect(link['href']).to eq(photo_url)
    expect(link['target']).to be_nil
    expect(link['aria-haspopup']).to eq('dialog')
    expect(link.at_css('img')['src']).to include('thumbnail=1')
    expect(response.parsed_body.at_css('.profile-photo figcaption .status-label-private').text).to eq('Private')
    expect(response.parsed_body.at_css('dialog')['aria-label']).to eq('Photo preview')
  end

  it 'keeps uploaded profile photos off the bookings and account details pages' do
    photo
    sign_in(participant)
    [profile_path, bookings_profile_path].each do |path|
      get path
      expect(response.parsed_body.css('main .photo-gallery, main .profile-photo')).to be_empty
    end
  end

  it 'uses the same popup links on public participant galleries' do
    photo.change_visibility(participant, true)
    get participant_path(participant)
    link = response.parsed_body.at_css('[data-photo-preview]')
    expect(link['href']).to eq(photo_url)
    expect(link['target']).to be_nil
    expect(response.parsed_body.at_css('[data-photo-dialog]')).not_to be_nil
    expect(response.parsed_body.at_css('.profile-tabs')).to be_nil
  end

  it 'keeps the owner photo editor in profile tabs and breadcrumbs' do
    sign_in(participant)
    get photos_profile_path
    expect(response.parsed_body.css('.profile-tabs a').map(&:text))
      .to eq(%w[Profile Edit Photos Security])
    expect(response.parsed_body.at_css('.profile-tabs [aria-current="page"]').text).to eq('Photos')
    expect(response.parsed_body.at_css('.breadcrumbs [aria-current="page"]').text).to eq('Photos')
    expect(response.parsed_body.at_css('form[action$="/photos"]')).to be_present
  end

  it 'accepts actual JPEG, PNG and WebP content rather than trusting filenames or supplied types' do
    %w[.jpg .png .webp].each do |format|
      saved = ProfilePhoto.add(participant.reload, photo_upload(format: format))
      expect(Vips::Image.new_from_buffer(saved.bytes, '').width).to eq(600)
    end
  end

  it 'hides private photos and thumbnails from guests on the public profile' do
    photo.change_visibility(participant, false)
    get participant_path(participant)
    expect(response.body).to include('Public Participant', 'No public photos.')
    expect(response.body).not_to include(photo.id.to_s)
    [photo_url, participant_photo_path(participant, photo.id, thumbnail: 1)].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'shows the next public booking but skips programs that hide the participant' do
    hidden, shown = Array.new(2) { create_program }
    grant_participant_access(hidden, participant).update!(photos_hidden: true)
    grant_participant_access(shown, participant)
    { hidden => 2, shown => 4 }.each do |target, days|
      starts_at = days.days.from_now.utc.change(hour: 17)
      track_booking Booking.create!(program: target, user: participant, date: starts_at.to_date, time_zone: 'UTC',
                                    starts_at: starts_at, ends_at: starts_at + 3.hours)
    end
    get participant_path(participant)
    expect(response.body).to include('Next Booking', shown.name)
    expect(response.body).not_to include(hidden.name)
  end

  it 'publishes only selected photos with public identity and no private account fields or edit controls' do
    photo.change_visibility(participant, true)
    hidden = ProfilePhoto.add(participant.reload, photo_upload)
    hidden.change_visibility(participant, false)
    get participant_path(participant)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Public Participant', photo.id.to_s)
    expect(response.body).not_to include(hidden.id.to_s, participant.name, participant.email, 'Upload Photo',
                                         'Delete Photo')
    get photo_url
    expect(response.media_type).to eq('image/webp')
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(Vips::Image.new_from_buffer(response.body, '').height).to eq(900)
  end

  it 'revokes previously public URLs immediately when a photo is made private' do
    photo.change_visibility(participant, true)
    guest = ActionDispatch::Integration::Session.new(Rails.application)
    guest.get(photo_url)
    expect(guest.response).to have_http_status(:ok)
    sign_in(participant)
    patch photo_url, params: { profile_photo: { public: '0' } }
    expect(response).to redirect_to(photos_profile_path)
    guest.get(photo_url)
    expect(guest.response).to have_http_status(:not_found)
    guest.get(participant_path(participant))
    expect(guest.response.body).not_to include(photo.id.to_s)
  end

  it 'hides public photos when the account is inactive without erasing photo preferences' do
    photo.change_visibility(participant, true)
    participant.update!(active: false)
    get photo_url
    expect(response).to have_http_status(:not_found)
    get participant_path(participant)
    expect(response).to have_http_status(:not_found)
    expect(participant.reload.profile_photos.first.public?).to be(true)
  end

  it 'lets assigned organizers see private photos but not upload, publish or delete them' do
    photo.change_visibility(participant, false)
    organizer = organizer_for(participant)
    sign_in(organizer)
    get photo_url
    expect(response).to have_http_status(:ok)
    get participant_path(participant)
    expect(response.body).to include('Public Participant', 'No public photos.')
    expect(response.body).not_to include('Account Participant', photo.id.to_s, 'Upload Photo', 'Make Public')
    post participant_photos_path(participant), params: { profile_photo: { file: photo_upload } }
    expect(response).to have_http_status(:forbidden)
    patch photo_url, params: { profile_photo: { public: '1' } }
    expect(response).to have_http_status(:forbidden)
    delete photo_url
    expect(response).to have_http_status(:forbidden)
  end

  it 'ends public gallery and image sharing after self-deactivation while privately retaining the photos' do
    photo.change_visibility(participant, true)
    organizer = organizer_for(participant)
    guest = ActionDispatch::Integration::Session.new(Rails.application)
    guest.get(photo_url)
    expect(guest.response).to have_http_status(:ok)
    sign_in(participant)
    post account_deactivation_path, params: { current_password: DatabaseHelpers::TEST_PASSWORD }
    [participant_path(participant), photo_url,
     participant_photo_path(participant, photo.id, thumbnail: 1)].each do |path|
      guest.get(path)
      expect(guest.response).to have_http_status(:not_found)
      expect(guest.response.headers['Cache-Control']).to include('no-store')
    end
    expect(participant.reload.profile_photos.first.public?).to be(true)
    sign_in(organizer)
    get photo_url
    expect(response).to have_http_status(:ok)
  end

  it 'denies unrelated organizers and removes private access when the organizer role is revoked' do
    photo.change_visibility(participant, false)
    organizer = organizer_for(participant)
    membership = ProgramMembership.coordinators.where(user_id: organizer.id).first
    sign_in(organizer)
    get photo_url
    expect(response).to have_http_status(:ok)
    membership.revoke_coordinator_access
    get photo_url
    expect(response).to have_http_status(:not_found)
  end

  it 'selects a primary photo from the gallery and makes it public' do
    first = photo
    second = ProfilePhoto.add(participant.reload, photo_upload)
    second.change_visibility(participant, false)
    sign_in(participant)
    get edit_profile_path
    expect(response.body).not_to include('Primary Profile Photo')
    get photos_profile_path
    expect(response.parsed_body.at_css("[data-photo='#{first.id}'] figcaption").text).to include('Primary')
    expect(response.parsed_body.at_css("[data-photo='#{first.id}']").text).not_to include('Make Primary')
    patch participant_photo_path(participant, second.id), params: { profile_photo: { primary: '1' } }
    expect(response).to redirect_to(photos_profile_path)
    expect(participant.reload.primary_profile_photo.id).to eq(second.id)
    expect(participant.profile_photos.map(&:public?)).to eq([true, true])
    get photos_profile_path
    expect(response.parsed_body.at_css("[data-photo='#{second.id}'] figcaption").text).to include('Primary')
  end

  it 'moves or clears the primary selection when the primary photo becomes private' do
    first = photo
    second = ProfilePhoto.add(participant.reload, photo_upload)
    third = ProfilePhoto.add(participant.reload, photo_upload)
    second.change_visibility(participant, false)
    sign_in(participant)
    patch participant_photo_path(participant, first.id), params: { profile_photo: { public: '0' } }
    expect(participant.reload.primary_profile_photo.id).to eq(third.id)
    patch participant_photo_path(participant, third.id), params: { profile_photo: { public: '0' } }
    expect(participant.reload.primary_profile_photo).to be_nil
    expect(participant.profile_photos.map(&:public?)).to eq([false, false, false])
    get photos_profile_path
    expect(response.parsed_body.css('.profile-photo .status-label').map(&:text)).not_to include('Primary')
  end

  it 'allows admin selection but rejects foreign photos and organizer selection' do
    photo
    sign_in(create_user(roles: ['system_admin']))
    get photos_admin_user_path(participant)
    expect(response.parsed_body.at_css("[data-photo='#{photo.id}'] figcaption").text).to include('Primary')
    patch photo_url, params: { profile_photo: { primary: '1' } }
    expect(response).to redirect_to(photos_admin_user_path(participant))
    patch participant_photo_path(create_user, photo.id), params: { profile_photo: { primary: '1' } }
    expect(response).to have_http_status(:not_found)
    sign_in(organizer_for(participant))
    patch photo_url, params: { profile_photo: { primary: '1' } }
    expect(response).to have_http_status(:forbidden)
  end

  it 'falls back to the first remaining photo after primary deletion' do
    first = photo
    second = ProfilePhoto.add(participant.reload, photo_upload)
    second.select_primary(participant)
    second.remove(participant)
    expect(participant.reload.primary_profile_photo_id).to be_nil
    expect(participant.primary_profile_photo.id).to eq(first.id)
    first.remove(participant)
    participant.reload
    expect(participant.primary_profile_photo).to be_nil
  end

  it 'does not clear a newer primary selection when deleting a stale photo' do
    first = photo
    second = ProfilePhoto.add(participant.reload, photo_upload)
    second.select_primary(participant)
    first.remove(participant)
    expect(participant.reload.primary_profile_photo.id).to eq(second.id)
  end

  it 'uses the selected primary thumbnail in model tables' do
    photo.change_visibility(participant, false)
    second = ProfilePhoto.add(participant.reload, photo_upload)
    second.change_visibility(participant, false)
    second.select_primary(participant)
    program = create_program
    grant_participant_access(program, participant)
    track_booking(BookingMutation.new(program: program, user: participant)
                   .book(date: Date.current.next_occurring(:monday).iso8601))
    sign_in(create_user(roles: ['system_admin']))
    { program_participants_path(program) => participant_path(participant),
      program_path(program, section: 'history') => participant_path(participant),
      admin_users_path => admin_user_path(participant) }.each do |path, link|
      get path
      url = participant_photo_path(participant, second.id, thumbnail: 1)
      expect(response.parsed_body.at_css(".participant-identity img[src='#{url}']")).to be_present
      expect(response.parsed_body.at_css(".participant-identity a[href='#{link}']")).to be_present
    end
  end

  it 'shows organizers and guests the same public profile without public photos' do
    participant.update!(instagram_handle: 'private.model')
    sign_in(organizer_for(participant))
    get participant_path(participant)
    expect(response.body).to include('Public Participant')
    expect(response.body).not_to include(participant.name, participant.email, '@private.model')
    participant.update!(instagram_tagging_allowed: true)
    get participant_path(participant)
    expect(response.body).to include('@private.model')
    delete session_path
    get participant_path(participant)
    expect(response.body).to include('Public Participant', '@private.model')
    expect(response.body).not_to include(participant.name)
  end

  it 'lets system admins manage another participant while preventing cross-owner photo IDs' do
    sign_in(create_user(roles: ['system_admin']))
    post participant_photos_path(participant), params: { profile_photo: { file: photo_upload } }
    saved = participant.reload.profile_photos.first
    patch participant_photo_path(participant, saved), params: { profile_photo: { public: '1' } }
    expect(participant.reload.profile_photos.first.public?).to be(true)
    foreign = create_user
    get participant_photo_path(foreign, saved)
    expect(response).to have_http_status(:not_found)
    delete participant_photo_path(participant, saved)
    expect(participant.reload.profile_photos).to be_empty
    expect(stored_files.count).to eq(0)
  end

  it 'requires authentication for writes and rejects ambiguous visibility values' do
    post participant_photos_path(participant), params: { profile_photo: { file: photo_upload } }
    expect(response).to redirect_to(new_session_path)
    sign_in(participant)
    patch photo_url, params: { profile_photo: { public: 'yes' } }
    expect(response).to have_http_status(:bad_request)
    expect(participant.reload.profile_photos.first.public?).to be(true)
    patch photo_url, params: { profile_photo: { primary: 'yes' } }
    expect(response).to have_http_status(:bad_request)
  end

  it 'rejects empty, corrupt, unsupported files and files over the size limit without storing them' do
    sign_in(participant)
    ['', "\xFF\xD8\xFF\xE0broken".b, '<svg xmlns="http://www.w3.org/2000/svg"/>', 'x' * 10_485_761].each do |bytes|
      post participant_photos_path(participant), params: { profile_photo: { file: raw_upload(bytes) } }
      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(response.body).to include('Choose')
      expect(participant.reload.profile_photos).to be_empty
      expect(stored_files.count).to eq(0)
    end
  end

  it 'rejects excessive decoded dimensions before generating or storing images' do
    upload = photo_upload(width: 10_000, height: 5000)
    expect { ProfilePhoto.add(participant, upload) }.to raise_error(ProfileImage::Invalid, /no larger than 10 MB/)
    expect(participant.reload.profile_photos).to be_empty
    expect(stored_files.count).to eq(0)
  end

  it 'keeps all concurrent uploads beyond ten photos and continues offering uploads' do
    9.times { ProfilePhoto.add(participant.reload, photo_upload) }
    owners = Array.new(2) { User.find(participant.id).tap { |user| user.profile_photos.to_a } }
    uploads = Array.new(2) { photo_upload }
    owners.zip(uploads).map { |owner, upload| Thread.new { ProfilePhoto.add(owner, upload) } }.each(&:value)
    expect(participant.reload.profile_photos.length).to eq(11)
    expect(stored_files.count).to eq(22)
    sign_in(participant)
    get photos_profile_path
    expect(response.parsed_body.at_css('input[type="file"]')).to be_present
    expect(response.body).not_to include('Delete one before uploading')
  end

  it 'cleans up uploads if the owning account disappears before attachment' do
    participant.destroy!
    expect { ProfilePhoto.add(participant, photo_upload) }.to raise_error(ProfileImage::Invalid, /no longer available/)
    expect(stored_files.count).to eq(0)
  end

  it 'allows replacement after deletion, removes both GridFS files and denies deleted URLs' do
    sign_in(participant)
    url = photo_url
    ids = [photo.image_id, photo.thumbnail_id]
    delete url
    expect(participant.reload.profile_photos).to be_empty
    expect(ProfilePhoto.storage.chunk_model.where(:files_id.in => ids).count).to eq(0)
    get url
    expect(response).to have_http_status(:not_found)
    post participant_photos_path(participant), params: { profile_photo: { file: photo_upload } }
    expect(participant.reload.profile_photos.length).to eq(1)
  end

  it 'cleans up both files when metadata persistence fails after image storage' do
    saved = ProfilePhoto.new
    allow(ProfilePhoto).to receive(:new).and_return(saved)
    allow(saved).to receive(:attach).and_raise(ProfileImage::Invalid, 'Upload could not be attached')
    expect { ProfilePhoto.add(participant, photo_upload) }.to raise_error(ProfileImage::Invalid)
    expect(stored_files.count).to eq(0)
    ids = [saved.image_id, saved.thumbnail_id]
    expect(ProfilePhoto.storage.chunk_model.where(:files_id.in => ids).count).to eq(0)
  end

  it 'reports storage errors without exposing private details or claiming upload success' do
    sign_in(participant)
    error = Mongo::Error.new('Private database details')
    allow(ProfilePhoto).to receive(:add).and_raise(error)
    allow(NewRelic::Agent).to receive(:notice_error)
    post participant_photos_path(participant), params: { profile_photo: { file: photo_upload } }
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).not_to include(error.message)
    expect(NewRelic::Agent).to have_received(:notice_error).with(error).once
  end
end
