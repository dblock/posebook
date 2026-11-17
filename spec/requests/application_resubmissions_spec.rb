# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reopening withdrawn applications', :aggregate_failures, :database, type: :request do
  let(:program) { create_program(applications_enabled: true) }
  let(:applicant) { create_user(email_verified_at: Time.current) }
  let(:coordinator) { create_user(email_verified_at: Time.current) }
  let(:workflow) { ParticipantApplicationWorkflow.new(program: program, user: applicant) }
  let(:application) { track_record(workflow.submit(message: 'My original experience', consent: '1')) }

  before do
    grant_coordinator_access(program, coordinator)
    sign_in(applicant)
  end

  def withdraw
    workflow.withdraw(application.id, version: application.reload.lock_version)
  end

  def reopen(version: application.reload.lock_version)
    post resubmit_program_participation_application_path(program), params: { lock_version: version }
  end

  def submit_again(consent)
    post program_participation_application_path(program),
         params: { participant_application: { intent: 'submit', consent: consent, message: 'Updated experience',
                                              lock_version: application.reload.draft_revision } }
  end

  it 'reopens only the owner withdrawn application privately without losing its message or history' do
    withdraw
    deliveries = EmailDelivery.count
    reopen
    expect(response).to redirect_to(new_program_participation_application_path(program))
    expect(application.reload).to have_attributes(status: 'draft', profile_shared_at: nil,
                                                  message: 'My original experience', lock_version: 2)
    expect(application.events.map(&:action)).to eq(%w[application_submitted application_withdrawn application_reopened])
    expect(EmailDelivery.count).to eq(deliveries)
    expect(program.participant?(applicant)).to be(false)
    sign_in(coordinator)
    get program_application_path(program, application)
    expect(response).to have_http_status(:not_found)
  end

  it 'requires fresh consent before an edited application can be submitted again' do
    withdraw
    reopen
    submit_again('0')
    expect(response).to have_http_status(:unprocessable_content)
    expect(application.reload).to have_attributes(status: 'draft', profile_shared_at: nil)
    submit_again('1')
    expect(response).to redirect_to(applications_profile_path)
    expect(application.reload).to have_attributes(status: 'pending', message: 'Updated experience', draft_origin: {})
    expect(application.events.map(&:action))
      .to eq(%w[application_submitted application_withdrawn application_reopened application_submitted])
  end

  it 'restores the withdrawn submission on cancellation and rejects old reopening forms' do
    withdraw
    version = application.reload.lock_version
    reopen
    ApplicationDraft.new(program: program, user: applicant)
                    .save(version: application.reload.draft_revision, message: 'Discard these changes')
    delete program_participation_application_path(program), params: { lock_version: application.reload.draft_revision }
    expect(application.reload).to have_attributes(status: 'withdrawn', message: 'My original experience',
                                                  draft_profile: {}, draft_origin: {})
    expect(application.events.map(&:action))
      .to eq(%w[application_submitted application_withdrawn application_reopened application_draft_abandoned])
    reopen(version: version)
    expect(response).to redirect_to(program_participation_application_path(program))
    expect(application.reload.status).to eq('withdrawn')
  end

  %w[draft pending declined accepted].each do |status|
    it "does not reopen #{status} applications" do
      application.update!(status: status)
      reopen
      expect(response).to redirect_to(program_participation_application_path(program))
      expect(application.reload.status).to eq(status)
    end
  end

  it 'rejects other accounts, closed programs, and stale or missing revisions' do
    withdraw
    [nil, '', 0, 'invalid'].each do |version|
      reopen(version: version)
      expect(application.reload.status).to eq('withdrawn')
    end
    sign_in(coordinator)
    reopen
    expect(response).to have_http_status(:not_found)
    sign_in(applicant)
    program.update!(applications_enabled: false)
    reopen
    expect(response).to have_http_status(:not_found)
    expect(application.reload.status).to eq('withdrawn')
  end

  it 'shows withdrawn and draft application details and history without edit or decision controls' do
    withdraw
    [false, true].each do |editing|
      reopen if editing
      get program_participation_application_path(program)
      expect(response).to have_http_status(:ok)
      main = response.parsed_body.at_css('main')
      expect(main.text).to include('My original experience', applicant.name, applicant.email, 'History')
      expect(main.css('input:not([type="hidden"]), select')).to be_empty
      expect(main.css('button').map(&:text)).to eq(editing ? [] : ['Resubmit'])
      expect(main.at_css("a[href='#{program_path(program)}']").text).to eq(program.name)
      expect(main.text).not_to include('This application cannot be accepted',
                                       'Application-only profile access has ended')
    end
  end

  it 'retains every repeated submission, withdrawal, and reopening in the owner history' do
    application
    2.times do
      withdraw
      reopen
      submit_again('1')
    end
    withdraw
    expect(application.events.pluck(:action))
      .to eq(%w[application_submitted application_withdrawn application_reopened application_submitted
                application_withdrawn application_reopened application_submitted application_withdrawn])
    get program_participation_application_path(program)
    labels = application.events.pluck(:action).reverse.map { |action| action.humanize.titleize }
    expect(response.parsed_body.css('[aria-label="Application history"] tbody tr td:first-child').map(&:text))
      .to eq(labels)
  end

  it 'keeps private draft transitions out of coordinator details and program history after submission' do
    withdraw
    reopen
    submit_again('1')
    sign_in(coordinator)
    [program_application_path(program, application), history_program_applications_path(program)].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Application Submitted', 'Application Withdrawn')
      expect(response.body).not_to include('Application Reopened')
    end
  end

  it 'rolls back both the state change and history if recording a new transition fails' do
    withdraw
    allow(ParticipationEvent).to receive(:create!).and_wrap_original do |original, **attributes|
      original.call(**attributes)
      raise ParticipantApplicationWorkflow::Invalid, 'History is unavailable.'
    end
    reopen
    expect(response).to have_http_status(:unprocessable_content)
    expect(application.reload.status).to eq('withdrawn')
    expect(application.events.pluck(:action)).to eq(%w[application_submitted application_withdrawn])
  end
end
