# frozen_string_literal: true

require 'rails_helper'
require 'vips'

RSpec.describe 'Single-page application drafts', :aggregate_failures, :database, type: :request do
  let(:program) { create_program(applications_enabled: true) }
  let(:applicant) { create_user(email_verified_at: Time.current) }
  let(:coordinator) { create_user }
  let(:draft) { ParticipantApplication.find_by(program_id: program.id, user_id: applicant.id) }
  let(:uploads) { [] }

  before do
    grant_coordinator_access(program, coordinator)
    sign_in(applicant)
  end

  after { uploads.each(&:close!) }

  def save_draft(**attributes)
    post program_participation_application_path(program),
         params: { participant_application: { intent: 'draft', message: 'Draft message' }.merge(attributes) }
  end

  def photo_upload
    file = Tempfile.new(['draft-photo', '.png'])
    file.binmode.write(Vips::Image.black(30, 40).new_from_image([160, 80, 60]).write_to_buffer('.png'))
    file.flush
    upload = Rack::Test::UploadedFile.new(file.path, 'image/png')
    uploads.push(file, upload.tempfile)
    upload
  end

  it 'shows account details and photos together without creating records on GET' do
    get new_program_participation_application_path(program)
    editor = response.parsed_body.at_css('#application-editor')
    expect(editor.css('input').pluck('name')).to include('participant_application[profile][name]',
                                                         'participant_application[profile][phone]',
                                                         'participant_application[photos][]')
    expect(editor.css('a[target="_blank"]')).to be_empty
    expect(ParticipantApplication.where(user_id: applicant.id)).not_to exist
    expect(response.body).to include('one completion reminder after seven days', 'after 30 days from the first save')
  end

  it 'saves incomplete details privately without changing the account, granting access, or notifying reviewers' do
    save_draft(profile: { name: '', phone: '', roles: ['system_admin'], email: 'forged@example.test' })
    expect(draft).to have_attributes(status: 'draft', profile_shared_at: nil, message: 'Draft message')
    expect(draft.draft_profile).to eq('name' => '', 'phone' => '')
    expect(applicant.reload.name).to eq('Test Participant')
    expect(program.participant?(applicant)).to be(false)
    expect(draft.events).to be_empty
    expect(EmailDelivery.where(resource_id: draft.id)).to be_empty
    follow_redirect!
    expect(response.parsed_body.at_css('[name="participant_application[profile][name]"]')['value']).to be_blank
    expect(response.body).to include('Abandon Draft', 'Draft saved.')
  end

  it 'excludes drafts from every manager listing and direct review endpoint' do
    save_draft
    sign_in(coordinator)
    get program_applications_path(program, status: 'all')
    expect(response.body).not_to include(applicant.email, 'Draft message')
    get program_application_path(program, draft)
    expect(response).to have_http_status(:not_found)
    patch program_application_path(program, draft),
          params: { participant_application: { status: 'accepted', lock_version: 0 } }
    expect(response).to have_http_status(:not_found)
    expect(draft.reload.status).to eq('draft')
  end

  it 'requires valid details and consent before atomically applying the saved profile and submitting' do
    save_draft(profile: { name: '' })
    save_draft(intent: 'submit', consent: '1', lock_version: draft.draft_revision)
    expect(response).to have_http_status(:unprocessable_content)
    expect(draft.reload.status).to eq('draft')
    expect(applicant.reload.name).to eq('Test Participant')
    save_draft(intent: 'submit', consent: '1', lock_version: draft.draft_revision, profile: { name: 'Ready Applicant' })
    expect(response).to redirect_to(program_participation_application_path(program))
    expect(draft.reload).to have_attributes(status: 'pending', name: 'Ready Applicant', draft_profile: {})
    expect(draft.submitted_at).to be_present
    expect(applicant.reload.name).to eq('Ready Applicant')
    expect(draft.events.pluck(:action)).to eq(['application_submitted'])
  end

  it 'rejects stale draft writes instead of replacing newer work or overwriting a submitted application' do
    save_draft
    version = draft.draft_revision
    save_draft(lock_version: version, message: 'Newer message')
    save_draft(lock_version: version, message: 'Stale message')
    expect(draft.reload.message).to eq('Newer message')
    save_draft(intent: 'submit', consent: '1', lock_version: draft.draft_revision)
    save_draft(lock_version: draft.draft_revision, message: 'Replace submitted')
    expect(draft.reload).to have_attributes(status: 'pending', message: 'Draft message')
  end

  it 'uploads and removes real photos on the same form while withholding draft-only reviewer access' do
    save_draft(photos: [photo_upload])
    photo = applicant.reload.profile_photos.first
    expect(photo.public?).to be(false)
    sign_in(coordinator)
    get participant_photo_path(applicant, photo)
    expect(response).to have_http_status(:not_found)
    sign_in(applicant)
    save_draft(lock_version: draft.draft_revision, remove_photo_id: photo.id.to_s)
    expect(applicant.reload.profile_photos).to be_empty
    expect(draft.reload.status).to eq('draft')
  end

  it 'abandons only the owner draft, retaining the account and photos and rejecting an old form' do
    save_draft(photos: [photo_upload])
    version = draft.draft_revision
    delete program_participation_application_path(program), params: { lock_version: version }
    expect(response).to redirect_to(program_path(program))
    expect(ParticipantApplication.where(user_id: applicant.id)).not_to exist
    expect(applicant.reload.profile_photos.size).to eq(1)
    save_draft(lock_version: version)
    expect(response).to redirect_to(new_program_participation_application_path(program))
    expect(ParticipantApplication.where(user_id: applicant.id)).not_to exist
  end

  it 'retains a saved draft on invalid uploads without submitting or exposing it to reviewers' do
    upload = photo_upload
    upload.tempfile.rewind
    upload.tempfile.truncate(0)
    upload.tempfile.write('not an image')
    upload.tempfile.rewind
    save_draft(intent: 'submit', consent: '1', photos: [upload])
    expect(response).to have_http_status(:unprocessable_content)
    expect(draft).to have_attributes(status: 'draft', profile_shared_at: nil)
    expect(applicant.reload.profile_photos).to be_empty
    expect(draft.events).to be_empty
  end

  it 'rejects old submission and abandonment forms after a draft is abandoned and replaced' do
    save_draft
    version = draft.draft_revision
    delete program_participation_application_path(program), params: { lock_version: version }
    save_draft(message: 'Replacement draft')
    replacement = ParticipantApplication.find_by(program_id: program.id, user_id: applicant.id)
    expect(replacement.id).not_to eq(draft.id)
    save_draft(intent: 'submit', consent: '1', lock_version: version, message: 'Stale form')
    delete program_participation_application_path(program), params: { lock_version: version }
    expect(replacement.reload).to have_attributes(status: 'draft', message: 'Replacement draft', lock_version: 0)
    expect(replacement.events).to be_empty
    save_draft(lock_version: replacement.draft_revision, message: 'Current form')
    expect(replacement.reload.message).to eq('Current form')
  end
end
