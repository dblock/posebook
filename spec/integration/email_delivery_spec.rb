# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailDelivery, :aggregate_failures, :database do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create_user }
  let(:program) { create_program }
  let(:organizer) { create_user(roles: ['system_admin']) }

  around do |example|
    previous_queues = Delayed::Worker.queues
    example.run
  ensure
    Delayed::Worker.queues = previous_queues
  end

  def enqueue_invitation(kind)
    invitation = if kind == 'participant_invitation'
                   create_participant_invitation(program, organizer, email: 'invitee@example.test')
                 else
                   create_coordinator_invitation(program.venue, organizer)
                 end
    enqueue(kind, invitation, token: invitation.token, expires_at: invitation.expires_at)
  end

  def enqueue(kind, resource, **attributes)
    track_record(described_class.enqueue(kind, resource, **attributes))
  end

  def booking_delivery
    membership = grant_participant_access(program, user)
    membership.update!(booking_invited_by_id: organizer.id)
    enqueue('booking_invitation', membership, grant_invited_at: membership.booking_invited_at)
  end

  def worker
    BackgroundWorker.build(queues: ['mailers'])
  end

  def retry_first_enqueue
    attempts = 0
    allow(EmailDeliveryJob).to receive(:perform_later).and_wrap_original do |original, *arguments|
      job = original.call(*arguments)
      attempts += 1
      if attempts == 1
        error = Mongo::Error::OperationFailure.new('Retry')
        error.add_label('TransientTransactionError')
        raise error
      end
      job
    end
  end

  it 'defers all five mail types to the real shared worker' do
    user.send_password_reset
    user.update_profile(email: 'pending@example.test', current_password: DatabaseHelpers::TEST_PASSWORD)
    enqueue_invitation('participant_invitation')
    enqueue_invitation('coordinator_invitation')
    booking_delivery
    expect(ActionMailer::Base.deliveries).to be_empty
    deliver_emails
    expect(ActionMailer::Base.deliveries.size).to eq(5)
    expect(ActionMailer::Base.deliveries.flat_map(&:to))
      .to include(user.email, 'pending@example.test', 'invitee@example.test')
    expect(described_class.where(:resource_id.in => tracked_records.map(&:id))).to be_empty
  end

  it 'keeps plaintext tokens and contacts out of persisted jobs and outbox attributes' do
    user.send_password_reset
    delivery = described_class.find_by(resource_id: user.id)
    queued = QueuedJob.find(delivery.queued_job_id)
    expect(queued.payload_object.job_data['arguments']).to eq([delivery.id.to_s])
    expect(queued.handler).not_to include(delivery.token, user.email, user.phone)
    expect(delivery.attributes.values).not_to include(delivery.token, user.email, user.phone)
    expect(User.for_password_reset(delivery.token)).to eq(user)
  end

  it 'sends only the latest recovery link without extending its original expiry' do
    user.send_password_reset
    old_token = described_class.find_by(resource_id: user.id).token
    delivery = user.send_password_reset
    expiry = user.reload.password_reset_expires_at
    deliver_emails
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.last.body.decoded).to include(delivery.token)
    expect(ActionMailer::Base.deliveries.last.body.decoded).not_to include(old_token)
    expect(user.reload.password_reset_expires_at).to eq(expiry)
  end

  it 'skips stale verification emails after another address is requested' do
    user.update_profile(email: 'first@example.test', current_password: DatabaseHelpers::TEST_PASSWORD)
    user.update_profile(email: 'second@example.test', current_password: DatabaseHelpers::TEST_PASSWORD)
    deliver_emails
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([['second@example.test']])
  end

  it 'reapplies profile changes and challenges after a transaction retry' do
    retry_first_enqueue
    user.update_profile(name: 'Updated Profile', email: 'pending@example.test',
                        current_password: DatabaseHelpers::TEST_PASSWORD)
    expect(user.reload).to have_attributes(name: 'Updated Profile', pending_email: 'pending@example.test')
    expect(user.history_tracks.where('modified.name' => 'Updated Profile').count).to eq(1)
    expect(described_class.where(resource_id: user.id).count).to eq(1)
    deliver_emails
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([['pending@example.test']])
  end

  it 'returns no queued delivery if preparation is rejected after a transaction retry' do
    retry_first_enqueue
    attempts = 0
    result = described_class.enqueue('password_reset', user, token: SecureRandom.urlsafe_base64(32),
                                                             expires_at: 30.minutes.from_now) do
      attempts += 1
      attempts == 1
    end
    expect(result).to be(false)
    expect(described_class.where(resource_id: user.id)).to be_empty
    expect(QueuedJob.where(queue: 'mailers')).to be_empty
  end

  it 'rolls back account challenges when database enqueueing fails without exposing private error text' do
    account = user
    error = Mongo::Error::OperationFailure.new('Private database details')
    allow(EmailDeliveryJob).to receive(:perform_later).and_raise(error)
    expect { account.send_password_reset }.to raise_error(described_class::Unavailable, error.class.name)
    expect(account.reload.password_reset_digest).to be_nil
    expect(account.password_reset_expires_at).to be_nil
    expect(described_class.where(resource_id: account.id)).to be_empty
    expect(QueuedJob.where(queue: 'mailers')).to be_empty
  end

  it 'rejects an outbox write outside its required workflow transaction' do
    described_class.with_session do |session|
      expect do
        described_class.enqueue_in_transaction('password_reset', user, session: session)
      end.to raise_error(described_class::Unavailable, 'Email enqueue requires an active transaction')
    end
    expect(described_class.where(resource_id: user.id)).to be_empty
    expect(QueuedJob.where(queue: 'mailers')).to be_empty
  end

  it 'rejects stale email-change credentials after a password change' do
    stale = User.find(user.id)
    user.change_password(current_password: DatabaseHelpers::TEST_PASSWORD,
                         password: 'a different sufficiently long password',
                         password_confirmation: 'a different sufficiently long password')
    expect(stale.update_profile(email: 'pending@example.test',
                                current_password: DatabaseHelpers::TEST_PASSWORD)).to be(false)
    expect(user.reload.pending_email).to be_nil
    expect(described_class.where(resource_id: user.id)).to be_empty
  end

  %w[email_change_expires_at active email_change_digest].each do |field|
    it "skips verification when #{field} invalidates its challenge" do
      user.update_profile(email: 'pending@example.test', current_password: DatabaseHelpers::TEST_PASSWORD)
      value = { 'email_change_expires_at' => 1.minute.ago, 'active' => false, 'email_change_digest' => nil }
      user.set(field => value.fetch(field))
      deliver_emails
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  %w[password_reset_expires_at active password_reset_digest].each do |field|
    it "skips recovery when #{field} invalidates its challenge" do
      user.send_password_reset
      value = { 'password_reset_expires_at' => 1.minute.ago, 'active' => false, 'password_reset_digest' => nil }
      user.set(field => value.fetch(field))
      deliver_emails
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(described_class.where(resource_id: user.id)).to be_empty
    end
  end

  %w[participant_invitation coordinator_invitation].each do |kind|
    %w[used_at revoked_at expires_at].each do |field|
      it "skips #{kind} when #{field} invalidates its token" do
        delivery = enqueue_invitation(kind)
        model = kind == 'participant_invitation' ? ParticipantInvitation : CoordinatorInvitation
        model.find(delivery.resource_id).set(field => 1.minute.ago)
        deliver_emails
        expect(ActionMailer::Base.deliveries).to be_empty
      end
    end

    it "rechecks the #{kind} sender's current permission" do
      enqueue_invitation(kind)
      organizer.set(roles: [])
      deliver_emails
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "skips #{kind} from an inactive sender" do
      enqueue_invitation(kind)
      organizer.set(active: false)
      deliver_emails
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  %w[participant_paused booking_invited_at roles].each do |field|
    it "skips booking invitations when #{field} invalidates the grant" do
      delivery = booking_delivery
      value = { 'participant_paused' => true, 'booking_invited_at' => 1.minute.from_now, 'roles' => [] }
      ProgramMembership.find(delivery.resource_id).set(field => value.fetch(field))
      deliver_emails
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it 'skips booking invitations after the participant books' do
    booking_delivery
    track_booking(BookingMutation.new(program: program, user: user).book(date: Date.current.next_occurring(:monday)))
    deliver_emails
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'skips booking invitations after the booking exhausts its grant' do
    booking_delivery
    booking = track_booking(BookingMutation.new(program: program,
                                                user: user).book(date: Date.current.next_occurring(:monday)))
    travel_to(booking.ends_at + 1.second) do
      deliver_emails
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  it 'skips booking invitations for inactive participants or unauthorized senders' do
    booking_delivery
    user.set(active: false)
    deliver_emails
    expect(ActionMailer::Base.deliveries).to be_empty
    user.set(active: true)
    booking_delivery
    organizer.set(roles: [])
    deliver_emails
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'retries SMTP failures safely and acknowledges successful delivery' do
    user.send_password_reset
    delivery = described_class.find_by(resource_id: user.id)
    output = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(output))
    adapter = Mail::TestMailer.new({})
    allow(Mail::TestMailer).to receive(:new).and_return(adapter)
    allow(PasswordResetMailer).to receive(:raise_delivery_errors).and_return(false)
    allow(adapter).to receive(:deliver!).and_raise(IOError, "#{user.email} #{delivery.token}")
    expect(worker.work_off(1)).to eq([0, 1])
    queued = QueuedJob.find(delivery.queued_job_id)
    expect(queued).to have_attributes(attempts: 1, last_error: EmailDelivery::Failed.name)
    expect(output.string).not_to include(user.email, delivery.token)
    allow(adapter).to receive(:deliver!).and_call_original
    queued.set(run_at: 1.second.ago)
    deliver_emails
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(described_class.where(id: delivery.id)).to be_empty
  end

  it 'retains valid email while the worker has delivery disabled' do
    user.send_password_reset
    delivery = described_class.find_by(resource_id: user.id)
    allow(Rails.configuration.x).to receive(:password_reset_delivery_enabled).and_return(false)
    expect(worker.work_off(1)).to eq([0, 1])
    expect(delivery.reload).to be_persisted
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it 'treats missing outbox records as harmless completed jobs' do
    delivery = track_record(described_class.new(id: BSON::ObjectId.new))
    job = EmailDeliveryJob.perform_later(delivery.id.to_s)
    delivery.queued_job_id = job.provider_job_id
    deliver_emails
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  %w[participation_event participation_admission].each do |kind|
    it "drops a queued #{kind} message when its source event no longer exists" do
      event = track_record(ParticipationEvent.create!(program: program, user: user, actor: organizer,
                                                      action: 'invitation_accepted', source_id: BSON::ObjectId.new))
      delivery = track_record(described_class.create!(kind: kind, resource_id: event.id, recipient_id: organizer.id))
      job = EmailDeliveryJob.perform_later(delivery.id.to_s)
      delivery.update!(queued_job_id: job.provider_job_id)
      event.destroy!
      deliver_emails
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(described_class.where(id: delivery.id)).to be_empty
      expect(QueuedJob.where(id: job.provider_job_id)).to be_empty
    end
  end
end
