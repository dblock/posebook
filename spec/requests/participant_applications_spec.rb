# frozen_string_literal: true

require 'rails_helper'
require 'vips'

RSpec.describe 'Participant applications', :aggregate_failures, :database, type: :request do
  let(:program) { create_program(applications_enabled: true, instructions: 'Private program instructions') }
  let(:applicant) do
    create_user(name: 'Original Applicant', email_verified_at: Time.current, public_profile_private: true)
  end
  let(:coordinator) { create_user(name: 'Reviewing Coordinator') }
  let(:application) do
    track_record(ParticipantApplicationWorkflow.new(program: program, user: applicant)
                                              .submit(message: 'A private application message.', consent: '1'))
  end

  before { grant_coordinator_access(program, coordinator) }

  def private_photo
    Tempfile.create(['application-photo', '.png']) do |file|
      file.binmode.write(Vips::Image.black(40, 60).new_from_image([160, 80, 60]).write_to_buffer('.png'))
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, 'image/png')
      ProfilePhoto.add(applicant, upload)
    ensure
      upload&.tempfile&.close!
    end
  end

  def decline_application
    application
    sign_in(coordinator)
    review('declined')
  end

  def review(status, version: application.reload.lock_version, notes: 'Private reviewer explanation.')
    patch program_application_path(program, application),
          params: { participant_application: { status: status, lock_version: version, notes: notes } }
  end

  it 'offers opt-in public applications without exposing private program information or granting access' do
    get program_path(program)
    expect(response.body).to include('Apply to Participate')
    expect(response.body).not_to include(program.instructions, 'Participation History')
    get new_program_participation_application_path(program)
    expect(response).to redirect_to(new_program_application_registration_path(program))
    sign_in(applicant)
    expect(response).to redirect_to(new_program_participation_application_path(program))
    follow_redirect!
    expect(response.body).to include('including private photos', 'Submit Application')
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(program.participant?(applicant)).to be(false)
  end

  it 'requires verification before allowing submission' do
    user = create_user
    sign_in(user)
    get new_program_participation_application_path(program)
    expect(response).to redirect_to(new_program_application_registration_path(program))
  end

  it 'requires explicit consent and ignores forged identity, role, and decision fields' do
    user = create_user
    sign_in(applicant)
    post program_participation_application_path(program),
         params: { participant_application: { message: 'Keep my draft', consent: '0' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('Keep my draft')
    expect(ParticipantApplication.where(user_id: applicant.id)).not_to exist
    post program_participation_application_path(program),
         params: { participant_application: { consent: '1', user_id: user.id, status: 'accepted',
                                              roles: ['system_admin'] } }
    expect(response).to redirect_to(program_participation_application_path(program))
    saved = ParticipantApplication.find_by(user_id: applicant.id)
    expect(saved).to have_attributes(status: 'pending', name: applicant.name, email: applicant.email,
                                     gender: applicant.gender, message: nil)
    expect(program.participant?(applicant)).to be(false)
    expect(applicant.reload.roles).to eq([])
  end

  it 'retains a bounded message, shows only the owner history, and prevents duplicate replacement' do
    sign_in(applicant)
    post program_participation_application_path(program),
         params: { participant_application: { message: 'x' * 5001, consent: '1' } }
    expect(response).to have_http_status(:unprocessable_content)
    application
    post program_participation_application_path(program),
         params: { participant_application: { message: 'Replacement', consent: '1' } }
    expect(response).to redirect_to(program_participation_application_path(program))
    expect(application.reload.message).to eq('A private application message.')
    get applications_profile_path
    expect(response.body).to include(program.name, 'Pending')
    get program_participation_application_path(program)
    expect(response.body).to include('Application Submitted', application.message)
  end

  it 'keeps other applicants out of the owner status and application list' do
    application
    sign_in(create_user)
    get program_participation_application_path(program)
    expect(response).to have_http_status(:not_found)
    get applications_profile_path
    expect(response.body).not_to include(program.name, application.message)
  end

  it 'retains private Not Now history and accepts it later even with intake closed' do
    decline_application
    expect(application.reload.status).to eq('declined')
    get program_application_path(program, application)
    expect(response.body).to include('Not Now', 'Private reviewer explanation.')
    expect(response.body).not_to include('>Not Now</button>')
    program.update!(applications_enabled: false)
    sign_in(coordinator)
    review('accepted')
    track_participant_membership(program, applicant)
    expect(program.participant?(applicant)).to be(true)
    expect(application.reload.status).to eq('accepted')
    get program_application_path(program, application)
    expect(response.body).to include('Application Submitted', 'Application: Not Now', 'Application Accepted')
    expect(response.body).not_to include('Private Reviewer Notes (Optional)')
  end

  it 'shows applicant decisions without disclosing reviewer notes or identity' do
    decline_application
    sign_in(applicant)
    get program_participation_application_path(program)
    expect(response.body).to include('Not Now', 'may accept this application later')
    expect(response.body).not_to include('Private reviewer explanation.', coordinator.name)
  end

  it 'rejects stale, missing, invalid, and excessively long decisions without granting access' do
    application
    sign_in(coordinator)
    [nil, 3].each do |version|
      review('accepted', version: version)
      expect(response).to redirect_to(program_application_path(program, application))
      expect(application.reload.status).to eq('pending')
    end
    review('withdrawn')
    expect(application.reload.status).to eq('pending')
    review('accepted', notes: 'x' * 201)
    expect(application.reload).to have_attributes(status: 'pending', lock_version: 0)
    expect(program.participant?(applicant)).to be(false)
  end

  it 'retains the private review destination through sign-in' do
    application
    get program_application_path(program, application)
    expect(response).to redirect_to(new_session_path)
    sign_in(coordinator)
    expect(response).to redirect_to(program_application_path(program, application))
    follow_redirect!
    expect(response.body).to include(applicant.email)
  end

  it 'scopes review, queues, and history to direct or inherited coordinators' do
    outsider = create_user
    sign_in(outsider)
    [program_applications_path(program), program_application_path(program, application),
     history_program_applications_path(program)].each do |path|
      get path
      expect(response).to have_http_status(:not_found)
    end
    foreign = create_program
    grant_coordinator_access(foreign, outsider)
    patch program_application_path(foreign, application),
          params: { participant_application: { status: 'accepted', lock_version: 0 } }
    expect(response).to have_http_status(:not_found)
    grant_venue_access(program.venue, outsider)
    get program_application_path(program, application)
    expect(response).to have_http_status(:ok)
    get program_applications_path(program, status: 'forged')
    expect(response).to have_http_status(:bad_request)
  end

  it 'grants consented photo review without permitting editing' do
    photo = private_photo
    sign_in(coordinator)
    get participant_photo_path(applicant, photo.id)
    expect(response).to have_http_status(:not_found)
    application
    get participant_path(applicant)
    expect(response.body).to include(applicant.email, 'Private', 'Profile photo 1')
    expect(response.body).not_to include('Delete Photo', 'Upload Photo')
    [nil, 1].each do |thumbnail|
      get participant_photo_path(applicant, photo.id, thumbnail: thumbnail)
      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to include('no-store')
    end
    patch participant_photo_path(applicant, photo.id), params: { profile_photo: { public: '1' } }
    expect(response).to have_http_status(:forbidden)
  end

  it 'requires a current owner revision to withdraw and ends direct image access and future acceptance' do
    photo = private_photo
    application
    sign_in(applicant)
    delete program_participation_application_path(program), params: { lock_version: 8 }
    expect(application.reload.status).to eq('pending')
    delete program_participation_application_path(program), params: { lock_version: 0 }
    expect(application.reload.status).to eq('withdrawn')
    sign_in(coordinator)
    [nil, 1].each do |thumbnail|
      get participant_photo_path(applicant, photo.id, thumbnail: thumbnail)
      expect(response).to have_http_status(:not_found)
    end
    review('accepted')
    expect(program.participant?(applicant)).to be(false)
  end

  it 'retains submission identity but not later private name changes after withdrawal' do
    application
    sign_in(applicant)
    delete program_participation_application_path(program), params: { lock_version: 0 }
    applicant.update!(name: 'Later Private Identity')
    sign_in(coordinator)
    get program_application_path(program, application)
    expect(response.body).to include('Original Applicant', 'Application Withdrawn')
    expect(response.body).not_to include('Later Private Identity', 'Review Current Profile')
    get history_program_applications_path(program)
    expect(response.body).not_to include('Later Private Identity')
  end

  it 'lists only scoped applications and retains gender in the shared contact label' do
    application
    sign_in(coordinator)
    get program_applications_path(program)
    expect(response.body).to include(applicant.email, "(#{applicant.gender.capitalize})", 'Review')
  end

  it 'distinguishes accepted invitations from applications in scoped participation history' do
    application
    invited = create_user(name: 'Invited Participant')
    invitation = create_participant_invitation(program, coordinator, name: invited.name, email: invited.email)
    InvitationAcceptance.new(token: invitation.token, user: invited).call
    track_participant_membership(program, invited)
    sign_in(coordinator)
    get history_program_applications_path(program)
    expect(response.body).to include('Invitation Accepted', 'Application Submitted', invited.email, applicant.email)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'allows scoped managers to configure opt-in and hides closed intake without losing applications' do
    application
    sign_in(coordinator)
    get edit_program_path(program)
    expect(response.body).to include('Accept Participation Applications')
    patch program_path(program), params: { program: { applications_enabled: '0' } }
    expect(program.reload.applications_enabled?).to be(false)
    get program_applications_path(program)
    expect(response.body).to include('Intake is closed', applicant.email)
    sign_in(create_user)
    get program_path(program)
    expect(response.body).not_to include('Apply to Participate')
    post program_participation_application_path(program),
         params: { participant_application: { consent: '1' } }
    expect(response).to have_http_status(:not_found)
  end

  it 'retains owner status but refuses new forms after intake closes' do
    application
    program.update!(applications_enabled: false)
    sign_in(applicant)
    get program_participation_application_path(program)
    expect(response).to have_http_status(:ok)
    get new_program_participation_application_path(program)
    expect(response).to have_http_status(:not_found)
  end
end
