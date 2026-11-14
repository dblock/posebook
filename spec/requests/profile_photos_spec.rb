# frozen_string_literal: true

require 'rails_helper'
require 'vips'

RSpec.describe 'Profile photos', :aggregate_failures, :database, type: :request do
  let(:model) { create_user(name: 'Account Artist', display_name: 'Public Artist') }
  let(:photo) { ProfilePhoto.add(model, photo_upload) }
  let(:photo_url) { model_photo_path(model, photo.id) }
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
    drawing_session = create_drawing_session
    grant_model_access(drawing_session, user)
    organizer = create_user
    grant_coordinator_access(drawing_session, organizer)
    organizer
  end

  def stored_files
    ProfilePhoto.storage.file_model.where('metadata.user_id' => model.id)
  end

  it 'uploads privately by default and offers square linked thumbnails and per-photo controls' do
    sign_in(model)
    post model_photos_path(model), params: { profile_photo: { file: photo_upload, public: '1' } }
    expect(response).to have_http_status(:see_other)
    expect(model.reload.profile_photos.map(&:public?)).to eq([false])
    follow_redirect!
    image = response.parsed_body.at_css('.profile-photo img')
    expect(image.attributes.transform_values(&:value)).to include('width' => '400', 'height' => '400')
    expect(response.body).to include('Make Public', 'Delete Photo', '1 of 10')
    expect(response.parsed_body.at_css('.profile-photo .status-label-neutral').text).to eq('Private')
  end

  it 'corrects orientation, strips metadata, preserves full-image proportions and creates optimized WebP squares' do
    upload = photo_upload(width: 2400, height: 1200, format: '.jpg', orientation: 6)
    saved = ProfilePhoto.add(model, upload)
    full = Vips::Image.new_from_buffer(saved.bytes, '')
    thumbnail = Vips::Image.new_from_buffer(saved.bytes(thumbnail: true), '')
    expect([full.width, full.height]).to eq([800, 1600])
    expect([thumbnail.width, thumbnail.height]).to eq([400, 400])
    expect(full.get('vips-loader')).to eq('webpload_buffer')
    expect(full.get_typeof('exif-data')).to eq(0)
    expect(full.get_typeof('orientation')).to eq(0)
    expect(saved.bytes.bytesize).to be < upload.tempfile.size
  end

  it 'accepts actual JPEG, PNG and WebP content rather than trusting filenames or supplied types' do
    %w[.jpg .png .webp].each do |format|
      saved = ProfilePhoto.add(model.reload, photo_upload(format: format))
      expect(Vips::Image.new_from_buffer(saved.bytes, '').width).to eq(600)
    end
  end

  it 'hides private galleries, full photos and thumbnails from guests' do
    photo
    [model_path(model), photo_url, model_photo_path(model, photo.id, thumbnail: 1)].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'publishes only selected photos with public identity and no private account fields or edit controls' do
    photo.change_visibility(model, true)
    hidden = ProfilePhoto.add(model.reload, photo_upload)
    get model_path(model)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Public Artist', photo.id.to_s)
    expect(response.body).not_to include(hidden.id.to_s, model.name, model.email, 'Upload Photo', 'Delete Photo')
    get photo_url
    expect(response.media_type).to eq('image/webp')
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(Vips::Image.new_from_buffer(response.body, '').height).to eq(900)
  end

  it 'revokes previously public URLs immediately when a photo is made private' do
    photo.change_visibility(model, true)
    guest = ActionDispatch::Integration::Session.new(Rails.application)
    guest.get(photo_url)
    expect(guest.response).to have_http_status(:ok)
    sign_in(model)
    patch photo_url, params: { profile_photo: { public: '0' } }
    expect(response).to redirect_to(model_path(model))
    guest.get(photo_url)
    expect(guest.response).to have_http_status(:not_found)
    guest.get(model_path(model))
    expect(guest.response).to have_http_status(:not_found)
  end

  it 'hides even public photos when identity is private or the account is inactive without erasing preferences' do
    photo.change_visibility(model, true)
    [{ public_profile_private: true }, { public_profile_private: false, active: false }].each do |attributes|
      model.reload.update!(attributes)
      get photo_url
      expect(response).to have_http_status(:not_found)
      get model_path(model)
      expect(response).to have_http_status(:not_found)
      expect(model.reload.profile_photos.first.public?).to be(true)
    end
  end

  it 'lets assigned organizers see private photos but not upload, publish or delete them' do
    organizer = organizer_for(model)
    sign_in(organizer)
    get photo_url
    expect(response).to have_http_status(:ok)
    get model_path(model)
    expect(response.body).to include('Account Artist', 'Private')
    expect(response.body).not_to include('Upload Photo', 'Make Public', 'Delete Photo')
    post model_photos_path(model), params: { profile_photo: { file: photo_upload } }
    expect(response).to have_http_status(:forbidden)
    patch photo_url, params: { profile_photo: { public: '1' } }
    expect(response).to have_http_status(:forbidden)
    delete photo_url
    expect(response).to have_http_status(:forbidden)
  end

  it 'denies unrelated organizers and removes private access when the organizer role is revoked' do
    organizer = organizer_for(model)
    membership = DrawingSessionMembership.coordinators.where(user_id: organizer.id).first
    sign_in(organizer)
    get photo_url
    expect(response).to have_http_status(:ok)
    membership.revoke_coordinator_access
    get photo_url
    expect(response).to have_http_status(:not_found)
    get model_path(model)
    expect(response).to have_http_status(:not_found)
  end

  it 'lets system admins manage another model while preventing cross-owner photo IDs' do
    sign_in(create_user(roles: ['system_admin']))
    post model_photos_path(model), params: { profile_photo: { file: photo_upload } }
    saved = model.reload.profile_photos.first
    patch model_photo_path(model, saved), params: { profile_photo: { public: '1' } }
    expect(model.reload.profile_photos.first.public?).to be(true)
    foreign = create_user
    get model_photo_path(foreign, saved)
    expect(response).to have_http_status(:not_found)
    delete model_photo_path(model, saved)
    expect(model.reload.profile_photos).to be_empty
    expect(stored_files.count).to eq(0)
  end

  it 'requires authentication for writes and rejects ambiguous visibility values' do
    post model_photos_path(model), params: { profile_photo: { file: photo_upload } }
    expect(response).to redirect_to(new_session_path)
    sign_in(model)
    patch photo_url, params: { profile_photo: { public: 'yes' } }
    expect(response).to have_http_status(:bad_request)
    expect(model.reload.profile_photos.first.public?).to be(false)
  end

  it 'rejects empty, corrupt, unsupported files and files over the size limit without storing them' do
    sign_in(model)
    ['', "\xFF\xD8\xFF\xE0broken".b, '<svg xmlns="http://www.w3.org/2000/svg"/>', 'x' * 10_485_761].each do |bytes|
      post model_photos_path(model), params: { profile_photo: { file: raw_upload(bytes) } }
      expect(response).to have_http_status(:see_other)
      follow_redirect!
      expect(response.body).to include('Choose')
      expect(model.reload.profile_photos).to be_empty
      expect(stored_files.count).to eq(0)
    end
  end

  it 'rejects excessive decoded dimensions before generating or storing images' do
    upload = photo_upload(width: 10_000, height: 5000)
    expect { ProfilePhoto.add(model, upload) }.to raise_error(ProfileImage::Invalid, /40 megapixels/)
    expect(model.reload.profile_photos).to be_empty
    expect(stored_files.count).to eq(0)
  end

  it 'enforces ten photos atomically under concurrent uploads and removes the losing upload files' do
    9.times { ProfilePhoto.add(model.reload, photo_upload) }
    owners = Array.new(2) { User.find(model.id).tap { |user| user.profile_photos.to_a } }
    uploads = Array.new(2) { photo_upload }
    results = owners.zip(uploads).map do |owner, upload|
      Thread.new do
        ProfilePhoto.add(owner, upload)
      rescue ProfileImage::Invalid
        nil
      end
    end.map(&:value)
    expect(results.compact.length).to eq(1)
    expect(model.reload.profile_photos.length).to eq(10)
    expect(stored_files.count).to eq(20)
  end

  it 'allows replacement after deletion, removes both GridFS files and denies deleted URLs' do
    sign_in(model)
    url = photo_url
    ids = [photo.image_id, photo.thumbnail_id]
    delete url
    expect(model.reload.profile_photos).to be_empty
    expect(ProfilePhoto.storage.chunk_model.where(:files_id.in => ids).count).to eq(0)
    get url
    expect(response).to have_http_status(:not_found)
    post model_photos_path(model), params: { profile_photo: { file: photo_upload } }
    expect(model.reload.profile_photos.length).to eq(1)
  end

  it 'cleans up both files when metadata persistence fails after image storage' do
    saved = ProfilePhoto.new
    allow(ProfilePhoto).to receive(:new).and_return(saved)
    allow(saved).to receive(:attach).and_raise(ProfileImage::Invalid, 'Upload could not be attached')
    expect { ProfilePhoto.add(model, photo_upload) }.to raise_error(ProfileImage::Invalid)
    expect(stored_files.count).to eq(0)
    ids = [saved.image_id, saved.thumbnail_id]
    expect(ProfilePhoto.storage.chunk_model.where(:files_id.in => ids).count).to eq(0)
  end

  it 'reports storage errors without exposing private details or claiming upload success' do
    sign_in(model)
    error = Mongo::Error.new('Private database details')
    allow(ProfilePhoto).to receive(:add).and_raise(error)
    allow(NewRelic::Agent).to receive(:notice_error)
    post model_photos_path(model), params: { profile_photo: { file: photo_upload } }
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).not_to include(error.message)
    expect(NewRelic::Agent).to have_received(:notice_error).with(error).once
  end
end
