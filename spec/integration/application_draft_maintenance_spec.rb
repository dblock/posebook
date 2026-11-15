# frozen_string_literal: true

require 'rails_helper'
require 'vips'

RSpec.describe ApplicationDraftMaintenance, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers
  include Rails.application.routes.url_helpers

  let(:program) { create_program(applications_enabled: true) }
  let(:user) { create_user(email_verified_at: Time.current) }
  let(:draft) do
    track_record(ParticipantApplication.create!(program: program, user: user, status: 'draft',
                                                message: 'Private draft message', created_at: 7.days.ago))
  end
  let(:maintenance) { described_class.new(draft.id) }

  around do |example|
    previous_queues = Delayed::Worker.queues
    travel_to(Time.utc(2026, 11, 15, 15)) { example.run }
  ensure
    Delayed::Worker.queues = previous_queues
  end

  after do
    QueuedJob.where(queue: 'maintenance').delete_all
    RecurringJobSchedule.where(id: ApplicationDraftMaintenanceJob.name).delete_all
  end

  def add_photo
    Tempfile.create(['draft-retention', '.png']) do |file|
      file.binmode.write(Vips::Image.black(30, 40).new_from_image([160, 80, 60]).write_to_buffer('.png'))
      file.flush
      ProfilePhoto.add(user, ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: 'photo.png',
                                                                    type: 'image/png'))
    end
  end

  def submit_or_expired
    ParticipantApplicationWorkflow.new(program: program, user: user)
                                  .submit(message: 'Ready to apply', consent: '1', version: draft.draft_revision)
    :submitted
  rescue ParticipantApplicationWorkflow::Conflict
    :expired
  end

  it 'starts at seven elapsed days and queues only one reminder without invalidating the open editor' do
    draft.update!(created_at: 7.days.ago + 1.second)
    described_class.run
    expect(draft.reload.draft_reminded_at).to be_nil
    travel 1.second
    2.times { described_class.run }
    expect(draft.reload).to have_attributes(draft_reminded_at: Time.current, lock_version: 0, status: 'draft')
    expect(EmailDelivery.where(resource_id: draft.id).count).to eq(1)
  end

  it 'sends a private authenticated resume or abandon link through the real mail worker' do
    maintenance.process
    delivery = EmailDelivery.find_by(resource_id: draft.id)
    queued = QueuedJob.find(delivery.queued_job_id)
    expect(queued.payload_object.job_data['arguments']).to eq([delivery.id.to_s])
    expect(queued.handler).not_to include(user.email, draft.message, user.phone)
    expect(delivery.attributes.values).not_to include(user.email, user.phone, draft.message)
    expect(delivery).to have_attributes(encrypted_token: nil, expires_at: draft.created_at + 30.days)
    deliver_emails
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([user.email])
    expect(mail.body.decoded).to include(program_participation_application_path(program), 'Abandon Draft',
                                         'Opening this link does not submit or abandon it', 'after 30 days')
    expect(mail.body.decoded).not_to include(draft.message, user.phone)
    expect(draft.events).to be_empty
    expect(program.participant?(user)).to be(false)
  end

  it 'uses first creation rather than recent edits to decide whether a reminder is due' do
    draft.update!(draft_profile: { 'name' => 'An unfinished edit' }, updated_at: Time.current)
    maintenance.process
    expect(draft.reload.draft_reminded_at).to eq(Time.current)
    expect(draft.created_at).to eq(7.days.ago)
  end

  it 'queues only one reminder across competing sweeps in the real database' do
    draft
    2.times.map { Thread.new { described_class.run } }.each(&:value)
    expect(EmailDelivery.where(resource_id: draft.id).count).to eq(1)
    deliver_emails
    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it 'rolls back the reminder marker, outbox, and real queue entry if enqueueing fails' do
    allow(EmailDeliveryJob).to receive(:perform_later).and_wrap_original do |original, *arguments|
      original.call(*arguments)
      raise ActiveJob::EnqueueError, 'Unavailable'
    end
    expect { maintenance.process }.to raise_error(EmailDelivery::Unavailable)
    expect(draft.reload.draft_reminded_at).to be_nil
    expect(EmailDelivery.where(resource_id: draft.id)).to be_empty
    expect(QueuedJob.where(queue: 'mailers')).to be_empty
  end

  it 'cleans up at thirty elapsed days without deleting accounts or actual account photos' do
    photo = add_photo
    draft.update!(created_at: 30.days.ago + 1.second, draft_reminded_at: 23.days.ago,
                  draft_profile: { 'name' => 'Incomplete' })
    described_class.run
    expect(ParticipantApplication.where(id: draft.id)).to exist
    travel 1.second
    described_class.run
    expect(ParticipantApplication.where(id: draft.id)).not_to exist
    expect(user.reload.name).to eq('Test Participant')
    expect(user.profile_photos.map(&:id)).to eq([photo.id])
    expect(EmailDelivery.where(resource_id: draft.id)).to be_empty
  end

  %w[pending accepted declined withdrawn].each do |status|
    it "retains #{status} applications after thirty days" do
      draft.update!(status: status, profile_shared_at: 40.days.ago, created_at: 40.days.ago)
      described_class.run
      expect(draft.reload.status).to eq(status)
    end
  end

  it 'does not remove a record with a profile-sharing timestamp even if its status is draft' do
    draft.update!(profile_shared_at: 40.days.ago, created_at: 40.days.ago)
    described_class.run
    expect(ParticipantApplication.where(id: draft.id)).to exist
  end

  it 'serializes expiry against submission without deleting submitted history or recreating a cleaned draft' do
    grant_coordinator_access(program, create_user)
    draft.update!(created_at: 30.days.ago)
    start = Queue.new
    tasks = [-> { maintenance.process }, -> { submit_or_expired }].map do |action|
      Thread.new do
        start.pop
        action.call
      end
    end
    2.times { start.push(true) }
    outcomes = tasks.map(&:value)
    remaining = ParticipantApplication.where(id: draft.id).first
    expect(remaining&.status).to be_nil.or(eq('pending'))
    expect(outcomes).to include(remaining ? :submitted : :expired)
    expect(ParticipationEvent.where(source_id: draft.id).count).to eq(remaining ? 1 : 0)
  end

  it 'skips an abandoned draft when its reminder reaches the mail worker' do
    maintenance.process
    ApplicationDraft.new(program: program, user: user).discard(version: draft.draft_revision)
    deliver_emails
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(EmailDelivery.where(resource_id: draft.id)).to be_empty
  end

  it 'skips a submitted draft when its reminder reaches the mail worker' do
    maintenance.process
    draft.update!(status: 'pending', profile_shared_at: Time.current)
    deliver_emails
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  %w[active email_verified_at].each do |field|
    it "rechecks #{field} before sending a reminder" do
      maintenance.process
      user.set(field => field == 'active' ? false : nil)
      deliver_emails
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  %w[applications_enabled active].each do |field|
    it "rechecks program #{field} before sending a reminder" do
      maintenance.process
      program.set(field => false)
      deliver_emails
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it 'rechecks venue availability and participation before queuing or sending a reminder' do
    program.venue.update!(active: false)
    maintenance.process
    expect(draft.reload.draft_reminded_at).to be_nil
    program.venue.update!(active: true)
    maintenance.process
    grant_participant_access(program, user)
    deliver_emails
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'never sends an expired reminder while preserving cleanup independent of account or intake state' do
    maintenance.process
    user.update!(active: false)
    program.update!(applications_enabled: false)
    travel 23.days
    deliver_emails
    expect(ActionMailer::Base.deliveries).to be_empty
    described_class.run
    expect(ParticipantApplication.where(id: draft.id)).not_to exist
    expect(user.reload).to be_persisted
  end

  it 'runs from the registered recurring maintenance queue through the real shared worker' do
    draft
    Delayed::Worker.queues = ['maintenance']
    RecurringJobSchedule.enqueue_due
    expect(draft.reload.draft_reminded_at).to be_nil
    expect(BackgroundWorker.build(queues: ['maintenance']).work_off(1)).to eq([1, 0])
    expect(draft.reload.draft_reminded_at).to eq(Time.current)
    deliver_emails
    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end
end
