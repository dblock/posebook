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

  def accept_invitation(inviter: coordinator)
    invitation = create_participant_invitation(program, inviter)
    InvitationAcceptance.new(token: invitation.token, user: applicant).call
    track_participant_membership(program, applicant)
    invitation
  end

  it 'does not revive an earlier submission email when a withdrawn application is submitted again' do
    ParticipantApplicationWorkflow.new(program: program, user: applicant).withdraw(application.id, version: 0)
    draft = ApplicationDraft.new(program: program, user: applicant).reopen(version: application.reload.lock_version)
    ParticipantApplicationWorkflow.new(program: program, user: applicant)
                                  .submit(message: 'Revised message', consent: '1', version: draft.draft_revision)
    deliver_emails
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.last.to).to eq([coordinator.email])
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

  it 'sends a courteous rejection only to the applicant and omits internal reasons' do
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
    mail = ActionMailer::Base.deliveries.find { |message| message.to == [applicant.email] }
    expect(mail.to).to eq([applicant.email])
    expect(mail.subject).to include('Application Accepted')
    expect(mail.body.decoded).to include(program_path(program, section: 'calendar'), 'any pause still apply')
    expect(mail.body.decoded).not_to include('Secret reviewer notes')
    notice = ActionMailer::Base.deliveries.find { |message| message.to == [coordinator.email] }
    expect(notice.subject).to include('Participation Accepted')
    expect(notice.body.decoded).to include('A participation application', applicant.name,
                                           history_program_applications_path(program))
    expect(notice.body.decoded).not_to include('Secret reviewer notes', application.message, applicant.email)
  end

  it 'drops superseded submission and Reject emails rather than sending them after acceptance' do
    decide('declined')
    decide('accepted')
    expect { deliver_emails }.to change { ActionMailer::Base.deliveries.length }.by(2)
    expect(ActionMailer::Base.deliveries.map(&:subject))
      .to contain_exactly("Application Accepted: #{program.name}", "Participation Accepted: #{program.name}")
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
    grant_venue_access(program.venue, create_user)
    calls = 0
    allow(EmailDeliveryJob).to receive(:perform_later).and_wrap_original do |original, *arguments|
      calls += 1
      calls < 3 ? original.call(*arguments) : false
    end
    expect { expect { decide('accepted') }.to raise_error(EmailDelivery::Unavailable) }.not_to change(QueuedJob, :count)
    expect(calls).to eq(3)
    expect(application.reload).to have_attributes(status: 'pending', lock_version: 0)
    expect(application.events.map(&:action)).to eq(['application_submitted'])
    expect(program.participant?(applicant)).to be(false)
  end

  it 'notifies active assigned coordinators once when a personal invitation is accepted' do
    inherited = create_user
    grant_venue_access(program.venue, inherited)
    grant_venue_access(program.venue, coordinator)
    grant_coordinator_access(program, create_user(active: false))
    create_user(roles: ['system_admin'])
    invitation = accept_invitation
    event = ParticipationEvent.find_by(source_id: invitation.id)
    deliveries = EmailDelivery.where(kind: 'participation_admission', resource_id: event.id)
    expect(deliveries.pluck(:recipient_id)).to contain_exactly(coordinator.id, inherited.id)
    handler = QueuedJob.find(deliveries.first.queued_job_id).handler
    expect(handler).to include(deliveries.first.id.to_s)
    expect(handler).not_to include(applicant.email, coordinator.email, invitation.token, applicant.name)
    deliver_emails
    expect(ActionMailer::Base.deliveries.map(&:to)).to contain_exactly([coordinator.email], [inherited.email])
    bodies = ActionMailer::Base.deliveries.map { |mail| mail.body.decoded }.join
    expect(bodies).to include('A personal invitation', applicant.name, history_program_applications_path(program))
    expect(bodies).not_to include(invitation.token, applicant.email)
  end

  it 'delivers completed acceptance after token expiry without allowing replay or another notification' do
    invitation = accept_invitation
    invitation.update!(expires_at: 1.day.ago)
    expect { deliver_emails }.to change { ActionMailer::Base.deliveries.length }.by(1)
    expect { InvitationAcceptance.new(token: invitation.token, user: applicant).call }
      .to raise_error(InvitationAcceptance::Unavailable)
    expect { deliver_emails }.not_to(change { ActionMailer::Base.deliveries.length })
  end

  it 'keeps applicant decisions separate when the accepted applicant is also an assigned coordinator' do
    grant_coordinator_access(program, applicant)
    decide('accepted')
    deliver_emails
    messages = ActionMailer::Base.deliveries.select { |mail| mail.to == [applicant.email] }
    expect(messages.map(&:subject))
      .to contain_exactly("Application Accepted: #{program.name}", "Participation Accepted: #{program.name}")
  end

  it 'preserves private invitation acceptance without SMTP or assigned notification recipients' do
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(false)
    invitation = accept_invitation
    expect(invitation.reload.used_by_id).to eq(applicant.id)
    expect(program.participant?(applicant)).to be(true)
    expect(EmailDelivery.where(resource_id: ParticipationEvent.find_by(source_id: invitation.id).id)).not_to exist
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(true)
    ProgramMembership.find_by(program_id: program.id, user_id: coordinator.id).revoke_coordinator_access
    second = accept_invitation(inviter: create_user(roles: ['system_admin']))
    expect(EmailDelivery.where(resource_id: ParticipationEvent.find_by(source_id: second.id).id)).not_to exist
  end

  it 'rolls invitation use, admission, history, and a real first job back if another recipient cannot queue' do
    grant_venue_access(program.venue, create_user)
    invitation = create_participant_invitation(program, coordinator)
    calls = 0
    allow(EmailDeliveryJob).to receive(:perform_later).and_wrap_original do |original, *arguments|
      calls += 1
      calls == 1 ? original.call(*arguments) : false
    end
    expect do
      expect { InvitationAcceptance.new(token: invitation.token, user: applicant).call }
        .to raise_error(EmailDelivery::Unavailable)
    end.not_to change(QueuedJob, :count)
    expect(calls).to eq(2)
    expect(invitation.reload.used_at).to be_nil
    expect(program.participant?(applicant)).to be(false)
    expect(ParticipationEvent.where(source_id: invitation.id)).not_to exist
    expect(EmailDelivery.where(kind: 'participation_admission')).not_to exist
  end

  it 'drops invitation acceptance notices after coordinator revocation or deactivation' do
    inherited = create_user
    grant_venue_access(program.venue, inherited)
    accept_invitation
    ProgramMembership.find_by(program_id: program.id, user_id: coordinator.id).revoke_coordinator_access
    inherited.update!(active: false)
    expect { deliver_emails }.not_to(change { ActionMailer::Base.deliveries.length })
  end

  it 'drops invitation acceptance notices after participation is revoked' do
    accept_invitation
    ProgramMembership.find_by(program_id: program.id, user_id: applicant.id).update!(roles: [])
    expect { deliver_emails }.not_to(change { ActionMailer::Base.deliveries.length })
  end

  it 'drops invitation acceptance notices after the participant becomes inactive' do
    accept_invitation
    applicant.update!(active: false)
    expect { deliver_emails }.not_to(change { ActionMailer::Base.deliveries.length })
  end

  it 'drops invitation acceptance notices after the parent venue becomes inactive' do
    accept_invitation
    program.venue.update!(active: false)
    expect { deliver_emails }.not_to(change { ActionMailer::Base.deliveries.length })
  end

  it 'binds admission notices to a matching accepted source and excludes other event actions' do
    application
    invitation = accept_invitation
    [create_program, program].each do |source_program|
      user = source_program == program ? create_user : applicant
      event = track_record(ParticipationEvent.create!(program: source_program, user: user, actor: coordinator,
                                                      action: 'invitation_accepted', source_id: invitation.id))
      expect(described_class.new(event).admission_message_for(coordinator.id)).to be_nil
    end
    event = track_record(ParticipationEvent.create!(program: program, user: applicant, actor: coordinator,
                                                    action: 'application_accepted', source_id: application.id))
    expect(described_class.new(event).admission_message_for(coordinator.id)).to be_nil
    expect(described_class.new(application.events.first).admission_message_for(coordinator.id)).to be_nil
  end

  it 'binds notification resources to the source program and applicant' do
    application
    event = track_record(ParticipationEvent.create!(program: create_program, user: applicant, actor: applicant,
                                                    action: 'application_submitted', source_id: application.id))
    expect(described_class.new(event).message_for(coordinator.id)).to be_nil
  end
end
