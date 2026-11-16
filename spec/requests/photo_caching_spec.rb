# frozen_string_literal: true

require 'rails_helper'
require 'vips'
require_relative '../../script/benchmark_user_experience'

RSpec.describe 'Photo cache validation', :aggregate_failures, :database, type: :request do
  let(:coordinator) { create_user }
  let(:program) { create_program }
  let(:uploads) { [] }

  after { uploads.each(&:close!) }

  def photo_upload
    file = Tempfile.new(['photo-cache', '.png'])
    file.binmode.write(Vips::Image.black(600, 900).write_to_buffer('.png'))
    file.flush
    upload = Rack::Test::UploadedFile.new(file.path, 'image/png')
    uploads.push(file, upload.tempfile)
    upload
  end

  def path
    route = owner.is_a?(User) ? :participant_photo_path : :"#{owner.class.model_name.singular}_photo_path"
    public_send(route, owner, photo.id)
  end

  def without_file_reads
    monitor = UserExperienceBenchmark::Commands.new
    Mongoid.default_client.subscribe(Mongo::Monitoring::COMMAND, monitor)
    yield
    expect(monitor.result[:collections].keys.grep(/\Aphotos\./)).to be_empty
  ensure
    Mongoid.default_client.unsubscribe(Mongo::Monitoring::COMMAND, monitor) if monitor
  end

  %i[profile venue program].each do |kind|
    context "with #{kind} photos" do
      let(:owner) do
        case kind
        when :profile then create_user
        when :venue then program.venue
        when :program then program
        end
      end
      let(:photo) do
        { profile: ProfilePhoto, venue: VenuePhoto, program: ProgramPhoto }.fetch(kind).add(owner, photo_upload)
      end

      before do
        grant_participant_access(program, owner) if kind == :profile
        kind == :venue ? grant_venue_access(owner, coordinator) : grant_coordinator_access(program, coordinator)
      end

      [false, true].each do |thumbnail|
        it "validates the #{thumbnail ? 'thumbnail' : 'full image'} without reading stored bytes" do
          get path, params: { thumbnail: thumbnail ? '1' : '0' }
          etag = response.headers.fetch('ETag')
          expect(response).to have_http_status(:ok)
          expect(response.headers['Cache-Control']).to eq('max-age=0, private, must-revalidate')
          without_file_reads do
            get path, params: { thumbnail: thumbnail ? '1' : '0' }, headers: { 'If-None-Match' => etag }
          end
          expect(response).to have_http_status(:not_modified)
          expect(response.body).to be_empty
          expect(response.headers['ETag']).to eq(etag)
          expect(response.headers['Cache-Control']).to eq('max-age=0, private, must-revalidate')
        end
      end

      it 'does not reuse the full image for a thumbnail or an unmatched ETag' do
        get path
        full_etag = response.headers.fetch('ETag')
        get path, params: { thumbnail: '1' }, headers: { 'If-None-Match' => full_etag }
        expect(response).to have_http_status(:ok)
        expect(response.headers['ETag']).not_to eq(full_etag)
        expect(Vips::Image.new_from_buffer(response.body, '').width).to eq(400)
        get path, headers: { 'If-None-Match' => '"unmatched"' }
        expect(response).to have_http_status(:ok)
        expect(response.headers['ETag']).to eq(full_etag)
        expect(Vips::Image.new_from_buffer(response.body, '').height).to eq(900)
      end

      it 'denies a previously public cached image after it becomes private' do
        get path
        etag = response.headers.fetch('ETag')
        sign_in(kind == :profile ? owner : coordinator)
        patch path, params: { "#{kind}_photo": { public: '0' } }
        expect(response).to have_http_status(:see_other)
        delete session_path
        get path, headers: { 'If-None-Match' => etag }
        expect(response).to have_http_status(:not_found)
      end

      it 'denies a cached image after its owner becomes inactive' do
        get path
        etag = response.headers.fetch('ETag')
        owner.update!(active: false)
        get path, headers: { 'If-None-Match' => etag }
        expect(response).to have_http_status(:not_found)
      end

      it 'denies a cached image after deletion' do
        get path
        etag = response.headers.fetch('ETag')
        sign_in(kind == :profile ? owner : coordinator)
        delete path
        expect(response).to have_http_status(:see_other)
        get path, headers: { 'If-None-Match' => etag }
        expect(response).to have_http_status(:not_found)
      end

      it 'rechecks private access before returning an unchanged response' do
        sign_in(kind == :profile ? owner : coordinator)
        patch path, params: { "#{kind}_photo": { public: '0' } }
        sign_in(coordinator) if kind == :profile
        get path
        etag = response.headers.fetch('ETag')
        get path, headers: { 'If-None-Match' => etag }
        expect(response).to have_http_status(:not_modified)
        membership = kind == :venue ? owner.memberships : program.memberships
        membership.find_by(user_id: coordinator.id).revoke_coordinator_access
        get path, headers: { 'If-None-Match' => etag }
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
