# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ParticipationNotification, :aggregate_failures, :database do
  include Rails.application.routes.url_helpers

  let(:program) { create_program(applications_enabled: true) }
  let(:coordinator) { create_user }
  let(:applicant) { create_user(email_verified_at: Time.current) }
  let(:application) do
    track_record(ParticipantApplicationWorkflow.new(program: program, user: applicant)
                                              .submit(message: 'Private application message', consent: '1'))
  end

  before { grant_coordinator_access(program, coordinator) }

  def decide(status)
    ParticipantApplicationWorkflow.new(program: program, user: coordinator)
                                  .review(application.id, status: status, version: application.reload.lock_version,
                                                          notes: 'Secret reviewer notes')
    track_participant_membership(program, applicant) if status == 'accepted'
  end

  it 'notifies each active assigned program or venue coordinator once without exposing the recipient list' do
    inherited = create_user
    grant_venue_access(program.venue, inherited)
    grant_venue_access(program.venue, coordinator)
    grant_coordinator_access(program, create_user(active: false))
    create_user(roles: ['system_admin'])
    application
    deliveries = EmailDelivery.where(:resource_id.in => application.events.pluck(:id))
    expect(deliveries.pluck(:recipient_id)).to contain_exactly(coordinator.id, inherited.id)
    deliver_emails
    messages = ActionMailer::Base.deliveries.last(2)
    expect(messages.map(&:to)).to contain_exactly([coordinator.email], [inherited.email])
    expect(messages.map { |mail| mail.body.decoded }.join).to include(program_application_path(program, application))
    expect(messages.map { |mail| mail.body.decoded }.join).not_to include(application.message)
  end

  it 'serializes only delivery IDs into jobs rather than emails, profiles, or reviewer notes' do
    application
    delivery = EmailDelivery.find_by(resource_id: application.events.first.id)
    handler = QueuedJob.find(delivery.queued_job_id).handler
    expect(handler).to include(delivery.id.to_s)
    expect(handler).not_to include(applicant.email, coordinator.email, application.message, 'Secret reviewer notes')
    expect(delivery.encrypted_token).to be_nil
  end

  it 'sends a courteous Not Now decision only to the applicant and omits internal reasons' do
    decide('declined')
    deliver_emails
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([applicant.email])
    expect(mail.body.decoded).to include('not accepting your application right now', 'future consideration',
                                         program_participation_application_path(program))
    expect(mail.body.decoded).not_to include('Secret reviewer notes')
  end

  it 'sends acceptance with the existing calendar path and honest booking constraints' do
    decide('accepted')
    deliver_emails
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([applicant.email])
    expect(mail.subject).to include('Application Accepted')
    expect(mail.body.decoded).to include(program_path(program, section: 'calendar'), 'any pause still apply')
    expect(mail.body.decoded).not_to include('Secret reviewer notes')
  end

  it 'drops superseded submission and Not Now emails rather than sending them after acceptance' do
    decide('declined')
    decide('accepted')
    expect { deliver_emails }.to change { ActionMailer::Base.deliveries.length }.by(1)
    expect(ActionMailer::Base.deliveries.last.subject).to include('Application Accepted')
  end

  it 'drops submission and decision emails after the owner withdraws' do
    decide('declined')
    ParticipantApplicationWorkflow.new(program: program, user: applicant)
                                  .withdraw(application.id, version: application.reload.lock_version)
    expect { deliver_emails }.not_to(change { ActionMailer::Base.deliveries.length })
    expect(EmailDelivery.where(:resource_id.in => application.events.pluck(:id))).not_to exist
  end

  it 'rechecks assigned coordinator authority immediately before building submission email' do
    application
    ProgramMembership.find_by(program_id: program.id, user_id: coordinator.id).revoke_coordinator_access
    expect { deliver_emails }.not_to(change { ActionMailer::Base.deliveries.length })
  end

  it 'does not send acceptance after participation is revoked' do
    decide('accepted')
    ProgramMembership.find_by(program_id: program.id, user_id: applicant.id).update!(roles: [])
    expect { deliver_emails }.not_to(change { ActionMailer::Base.deliveries.length })
  end

  it 'does not email inactive applicants' do
    decide('declined')
    applicant.update!(active: false)
    expect { deliver_emails }.not_to(change { ActionMailer::Base.deliveries.length })
  end

  it 'does not send decisions to a changed unverified address' do
    decide('declined')
    applicant.update!(email: "unverified-#{SecureRandom.hex(4)}@example.test", email_verified_at: nil)
    expect { deliver_emails }.not_to(change { ActionMailer::Base.deliveries.length })
  end

  it 'rolls submission and its history back when no active coordinator can be notified' do
    coordinator.update!(active: false)
    expect { application }.to raise_error(EmailDelivery::Unavailable)
    expect(ParticipantApplication.where(program_id: program.id)).not_to exist
    expect(ParticipationEvent.where(program_id: program.id)).not_to exist
  end

  it 'rolls back a real first queued job when a later recipient cannot be queued' do
    grant_venue_access(program.venue, create_user)
    calls = 0
    allow(EmailDeliveryJob).to receive(:perform_later).and_wrap_original do |original, *arguments|
      calls += 1
      calls == 1 ? original.call(*arguments) : false
    end
    expect { expect { application }.to raise_error(EmailDelivery::Unavailable) }.not_to change(QueuedJob, :count)
    expect(calls).to eq(2)
    expect(ParticipantApplication.where(program_id: program.id)).not_to exist
    expect(ParticipationEvent.where(program_id: program.id)).not_to exist
  end

  it 'rolls admission, revision, and decision history back when notification enqueue fails' do
    application
    allow(EmailDeliveryJob).to receive(:perform_later).and_return(false)
    expect { decide('accepted') }.to raise_error(EmailDelivery::Unavailable)
    expect(application.reload).to have_attributes(status: 'pending', lock_version: 0)
    expect(application.events.map(&:action)).to eq(['application_submitted'])
    expect(program.participant?(applicant)).to be(false)
  end

  it 'binds notification resources to the source program and applicant' do
    application
    event = track_record(ParticipationEvent.create!(program: create_program, user: applicant, actor: applicant,
                                                    action: 'application_submitted', source_id: application.id))
    expect(described_class.new(event).message_for(coordinator.id)).to be_nil
  end
end
