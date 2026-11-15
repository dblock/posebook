# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ParticipantApplicationWorkflow, :aggregate_failures, :database do
  let(:program) { create_program(applications_enabled: true) }
  let(:applicant) { create_user(email_verified_at: Time.current) }
  let(:coordinator) { create_user }

  before { grant_coordinator_access(program, coordinator) }

  def workflow(user = applicant)
    ParticipantApplicationWorkflow.new(program: program, user: user)
  end

  def submit
    workflow.submit(message: 'I would like to participate.', consent: '1')
  end

  def accept(application, **overrides)
    workflow(coordinator).review(application.id, status: 'accepted', version: application.lock_version,
                                                 **overrides)
  ensure
    record = ProgramMembership.where(program_id: program.id, user_id: applicant.id).first
    track_record(record) if record
  end

  it 'retains a consented, verified application without granting participation or booking access' do
    application = submit
    expect(application).to have_attributes(status: 'pending', lock_version: 0)
    expect(application.profile_shared_at).to be_present
    expect(program.participant?(applicant)).to be(false)
    expect(application.events.map(&:action)).to eq(['application_submitted'])
    expect(application.events.first.actor_id).to eq(applicant.id)
  end

  it 'can accept a past Not Now decision without losing its private explanation or reviewer' do
    application = submit
    workflow(coordinator).review(application.id, status: 'declined', version: 0, notes: 'Revisit next season.')
    expect(application.reload.status_label).to eq('Not Now')
    expect { workflow(coordinator).review(application.id, status: 'declined', version: 1) }
      .to raise_error(ParticipantApplicationWorkflow::Invalid)
    accept(application)
    expect(program.participant?(applicant)).to be(true)
    expect(ProgramMembership.find_by(program_id: program.id, user_id: applicant.id).booking_invited_at).to be_present
    expect(application.events.map(&:action)).to eq(%w[application_submitted application_declined application_accepted])
    expect(application.events.map(&:actor_id)).to eq([applicant.id, coordinator.id, coordinator.id])
    expect(application.events.where(action: 'application_declined').first.notes).to eq('Revisit next season.')
  end

  it 'requires current versions and prevents repeated or reversed accepted decisions' do
    application = submit
    [nil, '', '-1', 'invalid', 1].each do |version|
      expect { workflow(coordinator).review(application.id, status: 'accepted', version: version) }
        .to raise_error(ParticipantApplicationWorkflow::Conflict)
    end
    accept(application)
    expect { workflow(coordinator).review(application.id, status: 'declined', version: 1) }
      .to raise_error(ParticipantApplicationWorkflow::Conflict)
    expect(application.events.count).to eq(2)
  end

  it 'rejects duplicate submissions without replacing the original application or history' do
    application = submit
    expect { submit }.to raise_error(Mongo::Error::OperationFailure)
    expect(application.reload.message).to eq('I would like to participate.')
    expect(application.events.count).to eq(1)
  end

  it 'requires open active programs, fresh active users, verification, and explicit consent' do
    expect { workflow.submit(message: '', consent: '0') }.to raise_error(ParticipantApplicationWorkflow::Invalid)
    applicant.update!(email_verified_at: nil)
    expect { submit }.to raise_error(ParticipantApplicationWorkflow::Invalid)
    applicant.update!(email_verified_at: Time.current)
    program.update!(applications_enabled: false)
    expect { submit }.to raise_error(ParticipantApplicationWorkflow::Invalid)
    program.update!(applications_enabled: true)
    program.venue.update!(active: false)
    expect { submit }.to raise_error(ParticipantApplicationWorkflow::Invalid)
    program.venue.update!(active: true)
    applicant.update!(active: false)
    expect { submit }.to raise_error(Mongoid::Errors::DocumentNotFound)
  end

  it 'rechecks current manager authority and scopes application IDs to their program' do
    application = submit
    outsider = create_user
    expect { workflow(outsider).review(application.id, status: 'accepted', version: 0) }
      .to raise_error(Mongoid::Errors::DocumentNotFound)
    other = described_class.new(program: create_program, user: coordinator)
    expect { other.review(application.id, status: 'accepted', version: 0) }
      .to raise_error(Mongoid::Errors::DocumentNotFound)
    program.memberships.coordinators.find_by(user_id: coordinator.id).revoke_coordinator_access
    expect { accept(application) }.to raise_error(Mongoid::Errors::DocumentNotFound)
    expect(application.reload.status).to eq('pending')
  end

  it 'allows inherited venue coordinators and accepts retained applications after intake closes' do
    application = submit
    program.update!(applications_enabled: false)
    grant_venue_access(program.venue, coordinator)
    program.memberships.coordinators.find_by(user_id: coordinator.id).revoke_coordinator_access
    accept(application)
    expect(application.reload.status).to eq('accepted')
  end

  it 'rejects forged review transitions and refuses inactive accounts or locations' do
    application = submit
    expect { workflow(coordinator).review(application.id, status: 'withdrawn', version: 0) }
      .to raise_error(ParticipantApplicationWorkflow::Invalid)
    program.venue.update!(active: false)
    expect { accept(application) }.to raise_error(ParticipantApplicationWorkflow::Invalid)
    program.venue.update!(active: true)
    program.update!(active: false)
    expect { accept(application) }.to raise_error(ParticipantApplicationWorkflow::Invalid)
    program.update!(active: true)
    applicant.update!(active: false)
    expect { accept(application) }.to raise_error(Mongoid::Errors::DocumentNotFound)
    expect(application.reload.status).to eq('pending')
    expect(application.events.count).to eq(1)
  end

  it 'commits only one of competing acceptance and Not Now decisions' do
    application = submit
    threads = %w[accepted declined].map do |status|
      Thread.new do
        workflow(coordinator).review(application.id, status: status, version: 0)
        :saved
      rescue ParticipantApplicationWorkflow::Conflict
        :conflict
      end
    end
    expect(threads.map(&:value)).to contain_exactly(:saved, :conflict)
    track_record(ProgramMembership.where(program_id: program.id, user_id: applicant.id).first)
    expect(application.reload.lock_version).to eq(1)
    expect(application.events.count).to eq(2)
  end

  it 'does not renew an existing invitation cycle or bypass an existing participant pause' do
    application = submit
    membership = grant_participant_access(program, applicant)
    invited_at = 1.year.ago.change(usec: 0)
    membership.update!(booking_invited_at: invited_at, participant_paused: true, participant_pause_reason: 'On hold.')
    accept(application)
    expect(membership.reload).to have_attributes(booking_invited_at: invited_at, participant_paused: true)
  end

  it 'rolls back participation, application changes, and history when a decision cannot save' do
    application = submit
    expect { accept(application, notes: 'x' * 201) }.to raise_error(Mongoid::Errors::Validations)
    expect(application.reload).to have_attributes(status: 'pending', lock_version: 0)
    expect(program.participant?(applicant)).to be(false)
    expect(application.events.count).to eq(1)
  end

  it 'allows only the applicant to withdraw and retains history without allowing later acceptance' do
    application = submit
    expect { workflow(coordinator).withdraw(application.id, version: 0) }
      .to raise_error(Mongoid::Errors::DocumentNotFound)
    workflow.withdraw(application.id, version: 0)
    expect(application.reload.status).to eq('withdrawn')
    expect(application.events.map(&:action)).to eq(%w[application_submitted application_withdrawn])
    expect { accept(application) }.to raise_error(ParticipantApplicationWorkflow::Conflict)
  end

  it 'distinguishes existing invitation acceptance from application acceptance in retained history' do
    invitation = create_participant_invitation(program, coordinator, email: applicant.email)
    InvitationAcceptance.new(token: invitation.token, user: applicant).call
    track_participant_membership(program, applicant)
    event = ParticipationEvent.find_by(source_id: invitation.id)
    expect(event).to have_attributes(action: 'invitation_accepted', user_id: applicant.id, actor_id: coordinator.id)
    expect { submit }.to raise_error(ParticipantApplicationWorkflow::Invalid)
  end
end
