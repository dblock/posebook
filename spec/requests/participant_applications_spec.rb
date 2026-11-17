# frozen_string_literal: true

require 'rails_helper'
require 'vips'

RSpec.describe 'Participant applications', :aggregate_failures, :database, type: :request do
  let(:program) { create_program(applications_enabled: true, instructions: 'Private program instructions') }
  let(:applicant) do
    create_user(name: 'Original Applicant', email_verified_at: Time.current)
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
      photo = ProfilePhoto.add(applicant, upload)
      photo.change_visibility(applicant, false)
      photo
    ensure
      upload&.tempfile&.close!
    end
  end

  def decline_application
    application
    sign_in(coordinator)
    review('declined')
    expect(response).to redirect_to(program_applications_path(program))
  end

  def review(status, version: application.reload.lock_version, notes: 'Private reviewer explanation.')
    patch program_application_path(program, application),
          params: { participant_application: { status: status, lock_version: version, notes: notes } }
  end

  it 'offers opt-in public applications without exposing private program information or granting access' do
    get program_path(program)
    expect(response.body).to include('Apply to Participate')
    expect(response.body).to include("href=\"#{program_apply_path(program)}\"")
    expect(response.body).not_to include(program.instructions, 'Participation History')
    get new_program_participation_application_path(program)
    expect(response).to redirect_to(new_program_application_registration_path(program))
    sign_in(applicant)
    expect(response).to redirect_to(new_program_participation_application_path(program))
    follow_redirect!
    expect(response.body).to include("I agree to share my information with the program's coordinators.",
                                     'Submit Application')
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(program.participant?(applicant)).to be(false)
  end

  it 'redirects the shareable link through account preparation without submitting an application' do
    get program_apply_path(program)
    expect(response).to redirect_to(new_program_application_registration_path(program))
    expect(response.headers['Cache-Control']).to include('no-store')
    sign_in(applicant)
    expect(response).to redirect_to(new_program_participation_application_path(program))
    get program_apply_path(program)
    expect(response).to redirect_to(new_program_participation_application_path(program))
    expect(ParticipantApplication.where(program_id: program.id, user_id: applicant.id)).not_to exist
  end

  it 'keeps shareable links working after slug changes and accepts existing ID links' do
    original_path = program_apply_path(program)
    program.update!(custom_slug: "#{program.to_param}-renamed")
    sign_in(applicant)
    [original_path, program_apply_path(program.id)].each do |path|
      get path
      expect(response).to redirect_to(new_program_participation_application_path(program))
    end
    get program_apply_path('unknown-program')
    expect(response).to have_http_status(:not_found)
  end

  it 'routes existing applicants to their status and participants to their program' do
    application
    sign_in(applicant)
    get program_apply_path(program)
    expect(response).to redirect_to(program_participation_application_path(program))
    member = create_user(email_verified_at: Time.current)
    grant_participant_access(program, member)
    sign_in(member)
    get program_apply_path(program)
    expect(response).to redirect_to(program_path(program))
  end

  def expect_closed_landing
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Applications Closed', 'View Program', program_path(program))
  end

  it 'shows only a generic closed landing when either the program or its venue is inactive' do
    program.update!(active: false)
    get program_apply_path(program)
    expect_closed_landing
    expect(response.body).not_to include(program.name, program.instructions)
    program.update!(active: true)
    program.venue.update!(active: false)
    get program_apply_path(program)
    expect_closed_landing
  end

  it 'shows a closed landing for guests and signed-in applicants without creating application records' do
    program.update!(applications_enabled: false)
    get program_apply_path(program)
    expect_closed_landing
    sign_in(applicant)
    expect do
      get program_apply_path(program)
    end.not_to change(ParticipantApplication, :count)
    expect_closed_landing
    expect(ApplicationRegistration.where(program_id: program.id)).not_to exist
    expect(response.parsed_body.css('main form')).to be_empty
    expect(response.headers['Cache-Control']).to include('private', 'no-store')
  end

  it 'keeps intake off by default and lets coordinators toggle each program independently' do
    other = create_program
    grant_coordinator_access(other, coordinator)
    get program_apply_path(other)
    expect(response).to have_http_status(:ok)
    sign_in(coordinator)
    patch program_path(program), params: { program: { applications_enabled: '0' } }
    patch program_path(other), params: { program: { applications_enabled: '1' } }
    expect(program.reload.applications_enabled?).to be(false)
    expect(other.reload.applications_enabled?).to be(true)
    get program_apply_path(program)
    expect_closed_landing
    get program_apply_path(other)
    expect(response).to redirect_to(new_program_application_registration_path(other))
    patch program_path(program), params: { program: { applications_enabled: '1' } }
    expect(program.reload.applications_enabled?).to be(true)
    get program_apply_path(program)
    expect(response).to redirect_to(new_program_application_registration_path(program))
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
    draft = ParticipantApplication.find_by(user_id: applicant.id)
    expect(draft).to have_attributes(status: 'draft', profile_shared_at: nil, message: 'Keep my draft')
    post program_participation_application_path(program),
         params: { participant_application: { consent: '1', lock_version: draft.draft_revision,
                                              user_id: user.id, status: 'accepted',
                                              roles: ['system_admin'] } }
    expect(response).to redirect_to(applications_profile_path)
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

  def expect_accepted_application_links
    membership = program.memberships.participants.find_by(user_id: applicant.id)
    expect(response.parsed_body.at_css("main a[href='#{edit_program_participant_path(program,
                                                                                     membership)}']")).to be_present
    expect_applicant_profile_link
  end

  def expect_applicant_profile_link
    expect(response.parsed_body.at_css("main a[href='#{participant_path(applicant)}']").text).to eq('View Profile')
  end

  it 'links the applicant profile and labels Not Now with newest history first' do
    decline_application
    get program_application_path(program, application)
    header = response.parsed_body.at_css('main > p')
    expect(header.at_css('a')['href']).to eq(participant_path(applicant))
    expect(header.at_css('.status-label').text).to eq('Not Now')
    expect(header.text).not_to include(' - ')
    expect(response.parsed_body.css('[aria-label="Application history"] tbody tr td:first-child').map(&:text))
      .to eq(['Application: Not Now', 'Application Submitted'])
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
    expect_accepted_application_links
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

  it 'returns admission-email recipients to private history only within their management scope' do
    application
    get history_program_applications_path(program)
    expect(response).to redirect_to(new_session_path)
    sign_in(coordinator)
    expect(response).to redirect_to(history_program_applications_path(program))
    follow_redirect!
    expect(response.body).to include('Participation History', applicant.email)
    delete session_path
    get history_program_applications_path(program)
    sign_in(create_user)
    expect(response).to redirect_to(root_path)
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
    get program_application_path(program, application)
    expect(response.parsed_body.css('.photo-gallery [data-photo]').pluck('data-photo')).to eq([photo.id.to_s])
    expect(response.body).not_to include('Upload Photo')
    get participant_path(applicant)
    expect(response.body).not_to include(photo.id.to_s, 'Delete Photo', 'Upload Photo')
    [nil, 1].each do |thumbnail|
      get participant_photo_path(applicant, photo.id, thumbnail: thumbnail)
      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to eq('max-age=0, private, must-revalidate')
    end
    patch participant_photo_path(applicant, photo.id), params: { profile_photo: { public: '1' } }
    expect(response).to have_http_status(:forbidden)
  end

  it 'keeps owner application details and private photos available after withdrawal' do
    photo = private_photo
    application
    sign_in(applicant)
    delete program_participation_application_path(program), params: { lock_version: 0 }
    get program_participation_application_path(program)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(program.name, application.message, applicant.email,
                                     participant_photo_path(applicant, photo.id))
    get participant_photo_path(applicant, photo.id)
    expect(response).to have_http_status(:ok)
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

  it 'denies a cached private applicant image after consent is withdrawn' do
    photo = private_photo
    application
    sign_in(coordinator)
    path = participant_photo_path(applicant, photo.id)
    get path
    etag = response.headers.fetch('ETag')
    sign_in(applicant)
    delete program_participation_application_path(program), params: { lock_version: 0 }
    sign_in(coordinator)
    get path, headers: { 'If-None-Match' => etag }
    expect(response).to have_http_status(:not_found)
  end

  it 'retains submission identity but not later private name changes after withdrawal' do
    application
    sign_in(applicant)
    delete program_participation_application_path(program), params: { lock_version: 0 }
    applicant.update!(name: 'Later Account Name')
    sign_in(coordinator)
    get program_application_path(program, application)
    expect(response.body).to include('Original Applicant', 'Application Withdrawn')
    expect(response.body).not_to include('Later Account Name', 'photo-gallery')
    get history_program_applications_path(program)
    expect(response.body).not_to include('Later Account Name')
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
    expect(response.body).to include('Accept Participation Applications', program_apply_url(program))
    patch program_path(program), params: { program: { applications_enabled: '0' } }
    expect(program.reload.applications_enabled?).to be(false)
    get program_applications_path(program)
    expect(response.body).to include(applicant.email)
    expect(response.parsed_body.at_css('main .status-label').text).to eq('Closed')
    sign_in(create_user)
    get program_path(program)
    expect(response.body).not_to include('Apply to Participate')
    get program_apply_path(program)
    expect_closed_landing
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

  it 'retains the submitted draft and does not claim success when notifications cannot queue' do
    sign_in(applicant)
    allow(EmailDeliveryJob).to receive(:perform_later).and_return(false)
    post program_participation_application_path(program),
         params: { participant_application: { message: 'Keep my application draft', consent: '1' } }
    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).to include('Keep my application draft', 'Your draft was saved')
    expect(ParticipantApplication.find_by(user_id: applicant.id)).to have_attributes(status: 'draft',
                                                                                     profile_shared_at: nil)
  end

  it 'does not grant access or claim a saved decision when its notification cannot queue' do
    application
    sign_in(coordinator)
    allow(EmailDeliveryJob).to receive(:perform_later).and_return(false)
    review('accepted')
    expect(response).to redirect_to(program_application_path(program, application))
    follow_redirect!
    expect(response.body).to include('No application or decision was saved')
    expect(application.reload.status).to eq('pending')
    expect(program.participant?(applicant)).to be(false)
  end

  it 'returns authenticated decision-email recipients to their own status without exposing another account' do
    application
    get program_participation_application_path(program)
    sign_in(applicant)
    expect(response).to redirect_to(program_participation_application_path(program))
    delete session_path
    get program_participation_application_path(program)
    sign_in(create_user)
    expect(response).to redirect_to(root_path)
  end
end
