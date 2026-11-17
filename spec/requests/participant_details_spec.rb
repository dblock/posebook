# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Coordinator participant details', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:program) { create_program(participant_label: 'Model') }
  let(:coordinator) { create_user }
  let(:participant) do
    create_user(name: 'Original Account', display_name: 'Original Public')
  end
  let(:membership) { grant_participant_access(program, participant) }

  before do
    membership
    grant_coordinator_access(program, coordinator)
    sign_in(coordinator)
  end

  def update_details(**overrides)
    patch program_participant_path(program, membership),
          params: { participant: { display_name: ' Updated Public ',
                                   notes: " Private program note.\nSecond line. " }.merge(overrides) }
  end

  it 'shows saved account data separately from a public preview with no account-name fallback' do
    participant.update!(display_name: nil, instagram_handle: 'preview.model',
                        instagram_tagging_allowed: true)
    membership.update!(notes: 'Never public.')
    get edit_program_participant_path(program, membership)
    current = response.parsed_body.at_css('[data-current-profile]')
    preview = response.parsed_body.at_css('[data-public-preview]')
    expect(current.text).to include(participant.name, participant.email, participant.display_phone,
                                    'Not set (To be announced)')
    expect(preview.at_css('[data-public-preview-name]').text).to eq('To be announced')
    expect(preview.text).not_to include(participant.name)
    expect(preview.at_css('a')['href']).to eq(participant.public_instagram_url)
    expect(preview.text).not_to include(participant.email, participant.phone, participant.gender, 'Never public.')
  end

  it 'previews only public photos, never the private primary photo' do
    private_photo = participant.profile_photos.create!
    public_photo = participant.profile_photos.create!(public: true)
    get edit_program_participant_path(program, membership)
    current = response.parsed_body.at_css('[data-current-profile]')
    preview = response.parsed_body.at_css('[data-public-preview]')
    expect(current.at_css('img')['src']).to eq(participant_photo_path(participant, public_photo, thumbnail: 1))
    expect(response.body).not_to include(participant_photo_path(participant, private_photo, thumbnail: 1))
    expect(preview.css('img').pluck('src')).to eq([participant_photo_path(participant, public_photo, thumbnail: 1)])
    expect(preview.at_css('[data-public-preview-name]').text).to eq('Original Public')
  end

  it 'keeps inactive public previews anonymous despite the manager viewing private account data' do
    participant.update!(instagram_handle: 'hidden.model', instagram_tagging_allowed: true, active: false)
    participant.profile_photos.create!(public: true)
    get edit_program_participant_path(program, membership)
    preview = response.parsed_body.at_css('[data-public-preview]')
    expect(preview['data-public-preview-visible']).to eq('false')
    expect(preview.at_css('[data-public-preview-name]').text).to eq('To be announced')
    expect(preview.css('a, img')).to be_empty
    expect(preview.text).not_to include('Original Account', 'Original Public', 'hidden.model')
  end

  it 'keeps the user profile unchanged while previewing escaped override drafts after validation errors' do
    update_details(display_name: "<script>#{'x' * 100}</script>")
    expect(response).to have_http_status(:unprocessable_content)
    current = response.parsed_body.at_css('[data-current-profile]')
    preview = response.parsed_body.at_css('[data-public-preview]')
    expect(current.text).to include('Original Account', 'Original Public')
    expect(preview.at_css('[data-public-preview-name]').text).to start_with('<script>')
    expect(preview.css('img, script')).to be_empty
    expect(response.body).to include('Display Name is too long')
  end

  it 'saves a program-only display name override and notes with attributed history' do
    get edit_program_participant_path(program, membership)
    expect(response.parsed_body.at_css('#participant_name')).to be_nil
    field = response.parsed_body.at_css('#participant_display_name')
    expect([field['value'], field['placeholder']]).to eq([nil, 'Original Public'])
    expect(response.parsed_body.at_css('[data-public-preview-name]').text).to eq('Original Public')
    expect(response.parsed_body.at_css('input[type="submit"]')['value']).to eq('Save Model')
    expect(response.headers['Cache-Control']).to include('no-store')
    expect { update_details }.not_to(change { program.reload.schedule_revision })
    expect(response).to redirect_to(program_participants_path(program))
    expect(participant.reload).to have_attributes(name: 'Original Account', display_name: 'Original Public')
    expect(membership.reload).to have_attributes(display_name_override: 'Updated Public',
                                                 notes: "Private program note.\nSecond line.")
    expect(membership.participant_public_name).to eq('Updated Public')
    expect(membership.history_tracks.last.modifier_id).to eq(coordinator.id)
    get edit_program_participant_path(program, membership)
    expect(response.parsed_body.at_css('[data-current-profile]').text).to include('Original Public')
    expect(response.parsed_body.at_css('[data-public-preview-name]').text).to eq('Updated Public')
  end

  def book_on_programs(programs, date)
    programs.each do |target|
      track_booking Booking.create!(program: target, user: participant, date: date, status: 'confirmed',
                                    starts_at: Time.utc(2026, 11, 2, 17), ends_at: Time.utc(2026, 11, 2, 20),
                                    time_zone: 'UTC')
    end
  end

  def expect_other_manager_isolation(other)
    manager = create_user
    grant_coordinator_access(other.program, manager)
    sign_in(manager)
    get program_participants_path(other.program)
    expect_other_manager_notes
    get edit_program_participant_path(program, membership)
    expect(response).to have_http_status(:not_found)
  end

  def expect_other_manager_notes
    expect(response.body).to include('Other program note.')
    expect(response.body).not_to include('Private program note.')
  end

  it 'shows the override only on this program while isolating notes from other programs and their managers' do
    other = grant_participant_access(create_program, participant)
    other.update!(notes: 'Other program note.')
    update_details
    book_on_programs([program, other.program], Date.new(2026, 11, 2))
    travel_to(Time.utc(2026, 10, 30, 12)) do
      get calendar_program_path(program, month: '2026-11')
      expect(response.parsed_body.at_css('.booked-participant').text).to include('Updated Public')
      get calendar_program_path(other.program, month: '2026-11')
      expect(response.parsed_body.at_css('.booked-participant').text).to include('Original Public')
    end
    expect_other_manager_isolation(other)
  end

  it 'lets coordinators hide a public Instagram handle on this program only' do
    participant.update!(instagram_handle: 'shown.model', instagram_tagging_allowed: true)
    get edit_program_participant_path(program, membership)
    expect(response.parsed_body.at_css('[data-public-preview-instagram]')['hidden']).to be_nil
    update_details(instagram_hidden: '1')
    expect(membership.reload).to be_instagram_hidden
    get edit_program_participant_path(program, membership)
    expect(response.parsed_body.at_css('#participant_instagram_hidden')['checked']).to be_present
    expect(response.parsed_body.at_css('[data-public-preview-instagram]')['hidden']).not_to be_nil
    expect(response.parsed_body.at_css('[data-current-profile]').text).to include('@shown.model')
    expect(membership.participant_instagram_handle).to be_nil
    expect(participant.reload.public_instagram_handle).to eq('shown.model')
    update_details(instagram_hidden: '0')
    expect(membership.reload.participant_instagram_handle).to eq('shown.model')
    participant.update!(instagram_tagging_allowed: false)
    get edit_program_participant_path(program, membership)
    expect(response.parsed_body.at_css('#participant_instagram_hidden')['disabled']).to be_present
  end

  it 'lets coordinators hide public photos on this program only' do
    get edit_program_participant_path(program, membership)
    expect(response.parsed_body.at_css('#participant_photos_hidden')['disabled']).to be_present
    participant.profile_photos.create!(public: true)
    update_details(photos_hidden: '1')
    expect(membership.reload).to be_photos_hidden
    expect(participant.reload.public_photos).to be_any
    get edit_program_participant_path(program, membership)
    expect(response.parsed_body.at_css('#participant_photos_hidden')['checked']).to be_present
    expect(response.parsed_body.at_css('[data-public-preview-photos]')['hidden']).not_to be_nil
    update_details(photos_hidden: '0')
    expect(membership.reload).not_to be_photos_hidden
  end

  it 'cannot alter account, contact, role, access, or actor fields through the details form' do
    original = participant.attributes.slice('name', 'display_name', 'email', 'phone', 'gender', 'roles', 'active')
    update_details(name: 'Forged Name', email: 'forged@example.test', phone: '+12125559999', gender: 'male',
                   roles: ['system_admin'], active: false, participant_paused: true, booking_invited_at: nil,
                   modifier_id: participant.id, user_id: coordinator.id, program_id: create_program.id)
    expect(participant.reload.attributes.slice(*original.keys)).to eq(original)
    expect(membership.reload).not_to be_participant_paused
    expect(membership.booking_invited_at).to be_present
    expect(membership.user_id).to eq(participant.id)
  end

  it 'keeps both records unchanged on an invalid override and retains the submitted note for correction' do
    membership.update!(notes: 'Keep this note.')
    update_details(display_name: 'x' * 101)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.at_css('#participant_notes').text).to include('Private program note.')
    expect(participant.reload).to have_attributes(name: 'Original Account', display_name: 'Original Public')
    expect(membership.reload).to have_attributes(notes: 'Keep this note.', display_name_override: nil)
  end

  it 'supports inherited venue coordinators and admins even for inactive programs and participants' do
    participant.update!(active: false)
    program.update!(active: false)
    manager = create_user
    grant_venue_access(program.venue, manager)
    [manager, create_user(roles: ['system_admin'])].each do |actor|
      sign_in(actor)
      update_details
      expect(response).to redirect_to(program_participants_path(program))
    end
    expect(membership.reload.notes).to include('Private program note.')
  end

  it 'rejects foreign memberships and non-participant coordinator memberships' do
    foreign = grant_participant_access(create_program, create_user)
    peer = grant_coordinator_access(program, create_user)
    [foreign, peer].each do |record|
      get edit_program_participant_path(program, record)
      expect(response).to have_http_status(:not_found)
      patch program_participant_path(program, record), params: { participant: { notes: 'Forbidden.' } }
      expect(response).to have_http_status(:not_found)
      expect(record.reload.notes).to be_nil
    end
  end

  it 'keeps notes escaped and private from the participant, public pages, and personal profiles' do
    update_details(notes: "<script>alert('Private note')</script>\nSecond line.")
    get program_participants_path(program)
    expect(response.parsed_body.at_css('.participant-notes').text).to include('<script>')
    expect(response.parsed_body.at_css('.participant-notes script')).to be_nil
    sign_in(participant)
    [root_path, profile_path, photos_profile_path, program_path(program)].each do |path|
      get path
      expect(response.body).not_to include('Private note', 'Second line.')
    end
    get edit_program_participant_path(program, membership)
    expect(response).to have_http_status(:not_found)
    patch program_participant_path(program, membership), params: { participant: { notes: 'Forbidden.' } }
    expect(response).to have_http_status(:not_found)
  end

  it 'preserves omitted fields during partial updates and allows clearing optional fields' do
    update_details
    patch program_participant_path(program, membership), params: { participant: { notes: 'Notes only.' } }
    expect(membership.reload).to have_attributes(display_name_override: 'Updated Public', notes: 'Notes only.')
    patch program_participant_path(program, membership), params: { participant: { display_name: 'Name only.' } }
    expect(membership.reload).to have_attributes(display_name_override: 'Name only.', notes: 'Notes only.')
    update_details(display_name: ' ', notes: " \n ")
    expect(membership.reload).to have_attributes(display_name_override: nil, notes: nil)
    expect(membership.participant_public_name).to eq('Original Public')
  end

  it 'rechecks current privileges rather than trusting a previously authorized actor' do
    updater = ParticipantDetailsUpdate.new(program: program, user: coordinator)
    program.memberships.coordinators.find_by(user_id: coordinator.id).revoke_coordinator_access
    expect { updater.call(membership.id, display_name: 'Forbidden', notes: 'Forbidden') }
      .to raise_error(Mongoid::Errors::DocumentNotFound)
    expect(membership.reload).to have_attributes(display_name_override: nil, notes: nil)
    coordinator.update!(active: false)
    expect { updater.call(membership.id, notes: 'Forbidden') }.to raise_error(Mongoid::Errors::DocumentNotFound)
  end

  it 'rolls back the override, notes, and their history if the transaction cannot commit' do
    count = membership.history_tracks.count
    allow(ProgramMembership).to receive(:with_session).and_wrap_original do |original, &operation|
      original.call do |session|
        allow(session).to receive(:commit_transaction).and_raise(Mongo::Error::OperationFailure, 'Commit failed')
        operation.call(session)
      end
    end
    expect { update_details }.to raise_error(Mongo::Error::OperationFailure)
    expect(membership.reload).to have_attributes(display_name_override: nil, notes: nil)
    expect(membership.history_tracks.count).to eq(count)
  end
end
