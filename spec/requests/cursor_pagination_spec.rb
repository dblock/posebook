# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Application cursor pagination', :aggregate_failures, :database, type: :request do
  let(:coordinator) { create_user }
  let(:program) { create_program }
  let(:applicant) { create_user }
  let(:applications) do
    Array.new(3) do
      user = create_user
      track_record(ParticipantApplication.create!(program: program, user: user, name: user.name,
                                                  email: user.email, profile_shared_at: Time.current,
                                                  created_at: Time.utc(2026, 11, 14)))
    end
  end

  before do
    stub_const('CursorPage::PER_PAGE', 2)
    grant_coordinator_access(program, coordinator)
    applications
  end

  def review_rows
    response.parsed_body.css('tbody tr td:first-child').map(&:text)
  end

  it 'retains review filters and fresh authorization while paging through new submissions' do
    sign_in(coordinator)
    get program_applications_path(program, status: 'pending')
    next_path = response.parsed_body.at_css('a[rel="next"]')['href']
    expect(next_path).to include('status=pending', 'cursor=')
    first_names = review_rows
    expect(first_names).to eq(applications.reverse.first(2).map { |item| "#{item.name} <#{item.email}>" })
    track_record(ParticipantApplication.create!(program: program, user: applicant, name: 'New Applicant',
                                                profile_shared_at: Time.current))
    get next_path
    expect(review_rows).to eq(["#{applications.first.name} <#{applications.first.email}>"])
    expect(response.parsed_body.at_css('a[rel="next"]')).to be_nil
    previous_path = response.parsed_body.at_css('a[rel="prev"]')['href']
    get previous_path
    expect(review_rows).to eq(first_names)
    grant_coordinator_access(program, coordinator).set(roles: [])
    get next_path
    expect(response).to have_http_status(:not_found)
  end

  it 'restarts a cursor reused with a different status rather than applying a foreign boundary' do
    sign_in(coordinator)
    get program_applications_path(program, status: 'pending')
    next_path = response.parsed_body.at_css('a[rel="next"]')['href']
    applications.first.update!(status: 'declined')
    get next_path.sub('status=pending', 'status=declined')
    expect(response.body).to include(applications.first.email, 'Not Now')
    expect(response.parsed_body.at_css('.participant-pagination')).to be_nil
  end

  it 'paginates participation events while preserving source and actor display' do
    events = applications.map do |application|
      track_record(ParticipationEvent.create!(program: program, user: application.user, actor: coordinator,
                                              source_id: application.id, action: 'application_submitted',
                                              notes: application.email, created_at: Time.utc(2026, 11, 14)))
    end
    sign_in(coordinator)
    get history_program_applications_path(program)
    next_path = response.parsed_body.at_css('a[rel="next"]')['href']
    track_record(ParticipationEvent.create!(program: program, user: applicant, actor: coordinator,
                                            source_id: applications.last.id, action: 'application_declined'))
    get next_path
    expect(response.parsed_body.css('tbody tr').size).to eq(1)
    expect(response.parsed_body.at_css('tbody tr').text).to include(events.first.notes, coordinator.name)
    expect(response.parsed_body.at_css('a[rel="next"]')).to be_nil
  end

  it 'paginates owner applications without exposing another account or losing the reverse links' do
    owned = Array.new(3) do
      track_record(ParticipantApplication.create!(program: create_program, user: applicant,
                                                  profile_shared_at: Time.current,
                                                  created_at: Time.utc(2026, 11, 14) + Rational(1, 1000)))
    end
    sign_in(applicant)
    get applications_profile_path
    next_path = response.parsed_body.at_css('a[rel="next"]')['href']
    get next_path, params: { user_id: coordinator.id }
    expect(response.parsed_body.css('main li').map(&:text))
      .to eq(["#{owned.first.program.name} - Pending"])
    expect(response.parsed_body.at_css('a[rel="next"]')).to be_nil
    get response.parsed_body.at_css('a[rel="prev"]')['href']
    expect(response.parsed_body.css('main li').map(&:text))
      .to eq(owned.reverse.first(2).map { |item| "#{item.program.name} - Pending" })
  end
end
