# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Coordinator participant details', :aggregate_failures, :database, type: :request do
  let(:program) { create_program(participant_label: 'Model') }
  let(:coordinator) { create_user }
  let(:participant) do
    create_user(name: 'Original Account', display_name: 'Original Public', public_profile_private: true)
  end
  let(:membership) { grant_participant_access(program, participant) }

  before do
    membership
    grant_coordinator_access(program, coordinator)
    sign_in(coordinator)
  end

  def update_details(**overrides)
    patch program_participant_path(program, membership),
          params: { participant: { name: 'Updated Account', display_name: ' Updated Public ',
                                   notes: " Private program note.\nSecond line. " }.merge(overrides) }
  end

  it 'edits both names and program notes together with attributed history and unchanged privacy' do
    get edit_program_participant_path(program, membership)
    expect(response.parsed_body.at_css('#participant_name')['value']).to eq('Original Account')
    expect(response.parsed_body.at_css('#participant_display_name')['value']).to eq('Original Public')
    expect(response.parsed_body.at_css('input[type="submit"]')['value']).to eq('Save Model')
    expect(response.headers['Cache-Control']).to include('no-store')
    expect { update_details }.not_to(change { program.reload.schedule_revision })
    expect(response).to redirect_to(program_participants_path(program))
    expect(participant.reload).to have_attributes(name: 'Updated Account', display_name: 'Updated Public',
                                                  public_profile_private: true)
    expect(participant.public_name).to eq('To be announced')
    expect(membership.reload.notes).to eq("Private program note.\nSecond line.")
    expect([participant, membership].map { |record| record.history_tracks.last.modifier_id })
      .to eq([coordinator.id, coordinator.id])
    follow_redirect!
    expect(response.body).to include('Model details updated.')
  end

  it 'keeps names account-wide while isolating notes from other programs and their managers' do
    other = grant_participant_access(create_program, participant)
    other.update!(notes: 'Other program note.')
    update_details
    expect(other.reload.user.name).to eq('Updated Account')
    manager = create_user
    grant_coordinator_access(other.program, manager)
    sign_in(manager)
    get program_participants_path(other.program)
    expect(response.body).to include('Other program note.', 'Updated Account')
    expect(response.body).not_to include('Private program note.')
    get edit_program_participant_path(program, membership)
    expect(response).to have_http_status(:not_found)
  end

  it 'cannot alter contact, privacy, role, access, or actor fields through the details form' do
    original = participant.attributes.slice('email', 'phone', 'gender', 'roles', 'active', 'public_profile_private')
    update_details(email: 'forged@example.test', phone: '+12125559999', gender: 'male', roles: ['system_admin'],
                   active: false, public_profile_private: false, participant_paused: true, booking_invited_at: nil,
                   modifier_id: participant.id, user_id: coordinator.id, program_id: create_program.id)
    expect(participant.reload.attributes.slice(*original.keys)).to eq(original)
    expect(membership.reload).not_to be_participant_paused
    expect(membership.booking_invited_at).to be_present
    expect(membership.user_id).to eq(participant.id)
    expect(participant.history_tracks.last.modifier_id).to eq(coordinator.id)
  end

  it 'keeps both records unchanged on invalid names and retains the submitted note for correction' do
    membership.update!(notes: 'Keep this note.')
    [{ name: '' }, { display_name: 'x' * 101 }].each do |invalid|
      update_details(**invalid)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.at_css('#participant_notes').text).to include('Private program note.')
      expect(participant.reload).to have_attributes(name: 'Original Account', display_name: 'Original Public')
      expect(membership.reload.notes).to eq('Keep this note.')
    end
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
    [root_path, profile_path, participant_path(participant), program_path(program)].each do |path|
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
    expect(participant.reload.name).to eq('Updated Account')
    expect(membership.reload.notes).to eq('Notes only.')
    patch program_participant_path(program, membership), params: { participant: { name: 'Name only.' } }
    expect(participant.reload.display_name).to eq('Updated Public')
    expect(membership.reload.notes).to eq('Notes only.')
    update_details(display_name: ' ', notes: " \n ")
    expect(participant.reload.display_name).to be_nil
    expect(membership.reload.notes).to be_nil
  end

  it 'rechecks current privileges rather than trusting a previously authorized actor' do
    updater = ParticipantDetailsUpdate.new(program: program, user: coordinator)
    program.memberships.coordinators.find_by(user_id: coordinator.id).revoke_coordinator_access
    expect { updater.call(membership.id, name: 'Forbidden', notes: 'Forbidden') }
      .to raise_error(Mongoid::Errors::DocumentNotFound)
    expect(participant.reload.name).to eq('Original Account')
    expect(membership.reload.notes).to be_nil
    coordinator.update!(active: false)
    expect { updater.call(membership.id, notes: 'Forbidden') }.to raise_error(Mongoid::Errors::DocumentNotFound)
  end

  it 'rolls back both names, notes, and their history if the transaction cannot commit' do
    counts = [participant, membership].map { |record| record.history_tracks.count }
    allow(ProgramMembership).to receive(:with_session).and_wrap_original do |original, &operation|
      original.call do |session|
        allow(session).to receive(:commit_transaction).and_raise(Mongo::Error::OperationFailure, 'Commit failed')
        operation.call(session)
      end
    end
    expect { update_details }.to raise_error(Mongo::Error::OperationFailure)
    expect(participant.reload.name).to eq('Original Account')
    expect(membership.reload.notes).to be_nil
    expect([participant, membership].map { |record| record.history_tracks.count }).to eq(counts)
  end
end
