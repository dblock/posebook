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

  it 'uploads privately by default and offers square linked thumbnails and per-photo controls' do
    sign_in(participant)
    post participant_photos_path(participant), params: { profile_photo: { file: photo_upload, public: '1' } }
    expect(response).to have_http_status(:see_other)
    expect(participant.reload.profile_photos.map(&:public?)).to eq([false])
    follow_redirect!
    image = response.parsed_body.at_css('.profile-photo img')
    expect(image.attributes.transform_values(&:value)).to include('width' => '400', 'height' => '400')
    expect(response.body).to include('Make Public', 'Delete Photo', '1 of 10')
    expect(response.parsed_body.css('.photo-actions button.secondary-action').map(&:text))
      .to contain_exactly('Make Public', 'Delete Photo')
    expect(response.parsed_body.at_css('.profile-photo .status-label-neutral').text).to eq('Private')
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

  it 'shows private photos on the owner profile with full-image popup links' do
    photo
    participant.update!(public_profile_private: true)
    sign_in(participant)
    get profile_path
    link = response.parsed_body.at_css('.profile-photo [data-photo-preview]')
    expect(link['href']).to eq(photo_url)
    expect(link['target']).to be_nil
    expect(link['aria-haspopup']).to eq('dialog')
    expect(link.at_css('img')['src']).to include('thumbnail=1')
    expect(response.parsed_body.at_css('.profile-photo figcaption').text).to eq('Private')
    expect(response.parsed_body.at_css('dialog')['aria-labelledby']).to eq('photo-preview-heading')
  end

  it 'omits the photo section on an empty account profile' do
    sign_in(participant)
    get profile_path
    expect(response.parsed_body.at_css('#profile-photos-heading')).to be_nil
    expect(response.parsed_body.css('.profile-photo')).to be_empty
  end

  it 'uses the same popup links on public participant galleries' do
    photo.change_visibility(participant, true)
    get participant_path(participant)
    link = response.parsed_body.at_css('[data-photo-preview]')
    expect(link['href']).to eq(photo_url)
    expect(link['target']).to be_nil
    expect(response.parsed_body.at_css('[data-photo-dialog]')).not_to be_nil
  end

  it 'accepts actual JPEG, PNG and WebP content rather than trusting filenames or supplied types' do
    %w[.jpg .png .webp].each do |format|
      saved = ProfilePhoto.add(participant.reload, photo_upload(format: format))
      expect(Vips::Image.new_from_buffer(saved.bytes, '').width).to eq(600)
    end
  end

  it 'hides private galleries, full photos and thumbnails from guests' do
    photo
    [participant_path(participant), photo_url,
     participant_photo_path(participant, photo.id, thumbnail: 1)].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'publishes only selected photos with public identity and no private account fields or edit controls' do
    photo.change_visibility(participant, true)
    hidden = ProfilePhoto.add(participant.reload, photo_upload)
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
    expect(response).to redirect_to(participant_path(participant))
    guest.get(photo_url)
    expect(guest.response).to have_http_status(:not_found)
    guest.get(participant_path(participant))
    expect(guest.response).to have_http_status(:not_found)
  end

  it 'hides even public photos when identity is private or the account is inactive without erasing preferences' do
    photo.change_visibility(participant, true)
    [{ public_profile_private: true }, { public_profile_private: false, active: false }].each do |attributes|
      participant.reload.update!(attributes)
      get photo_url
      expect(response).to have_http_status(:not_found)
      get participant_path(participant)
      expect(response).to have_http_status(:not_found)
      expect(participant.reload.profile_photos.first.public?).to be(true)
    end
  end

  it 'lets assigned organizers see private photos but not upload, publish or delete them' do
    organizer = organizer_for(participant)
    sign_in(organizer)
    get photo_url
    expect(response).to have_http_status(:ok)
    get participant_path(participant)
    expect(response.body).to include('Account Participant', 'Private')
    expect(response.body).not_to include('Upload Photo', 'Make Public', 'Delete Photo')
    post participant_photos_path(participant), params: { profile_photo: { file: photo_upload } }
    expect(response).to have_http_status(:forbidden)
    patch photo_url, params: { profile_photo: { public: '1' } }
    expect(response).to have_http_status(:forbidden)
    delete photo_url
    expect(response).to have_http_status(:forbidden)
  end

  it 'denies unrelated organizers and removes private access when the organizer role is revoked' do
    organizer = organizer_for(participant)
    membership = ProgramMembership.coordinators.where(user_id: organizer.id).first
    sign_in(organizer)
    get photo_url
    expect(response).to have_http_status(:ok)
    membership.revoke_coordinator_access
    get photo_url
    expect(response).to have_http_status(:not_found)
    get participant_path(participant)
    expect(response).to have_http_status(:not_found)
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
    expect(participant.reload.profile_photos.first.public?).to be(false)
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
    expect { ProfilePhoto.add(participant, upload) }.to raise_error(ProfileImage::Invalid, /40 megapixels/)
    expect(participant.reload.profile_photos).to be_empty
    expect(stored_files.count).to eq(0)
  end

  it 'enforces ten photos atomically under concurrent uploads and removes the losing upload files' do
    9.times { ProfilePhoto.add(participant.reload, photo_upload) }
    owners = Array.new(2) { User.find(participant.id).tap { |user| user.profile_photos.to_a } }
    uploads = Array.new(2) { photo_upload }
    results = owners.zip(uploads).map do |owner, upload|
      Thread.new do
        ProfilePhoto.add(owner, upload)
      rescue ProfileImage::Invalid
        nil
      end
    end.map(&:value)
    expect(results.compact.length).to eq(1)
    expect(participant.reload.profile_photos.length).to eq(10)
    expect(stored_files.count).to eq(20)
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
