# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Administrator audit history', :aggregate_failures, :database, type: :request do
  let(:admin) { create_user(name: 'Audit Administrator', roles: ['system_admin']) }

  def history_row(entry)
    response.parsed_body.at_css("tr[data-history='#{entry.id}']")
  end

  def change_program_records(program, membership, exception)
    Current.set(user: admin) do
      program.venue.update!(address: 'Updated address')
      program.update!(instructions: 'Updated instructions')
      membership.update!(notes: 'Updated notes')
      exception.update!(reason: 'Updated closure reason.')
    end
  end

  it 'requires an active system administrator and hides the link from every other audience' do
    admin
    get admin_history_path
    expect(response).to redirect_to(new_session_path)
    coordinator = create_user
    grant_venue_access(create_venue, coordinator)
    [create_user, coordinator].each do |user|
      sign_in(user)
      get profile_path
      expect(response.parsed_body.at_css("header a[href='#{admin_history_path}']")).to be_nil
      get admin_history_path
      expect(response).to have_http_status(:forbidden)
    end
  end

  it 'displays real attributed changes with actor and subject links but no untracked fields or unsafe markup' do
    user = create_user(name: 'Original Name')
    sign_in(admin)
    patch admin_user_path(user), params: { user: { name: '<script>changed</script>', email: user.email } }
    entry = user.history_tracks.last
    entry.set(modified: entry.modified.merge('password_digest' => 'synthetic secret'))
    get admin_history_path
    row = history_row(entry)
    expect(row.at_css("a[href='#{admin_user_path(admin)}']").text).to eq(admin.name)
    expect(row.at_css("a[href='#{admin_user_path(user)}']").text).to eq('<script>changed</script>')
    expect(row.text).to include('Original Name', '<script>changed</script>', 'Updated', 'Before:', 'After:')
    expect(row.at_css('script')).to be_nil
    expect(response.body).not_to include('synthetic secret', 'Password digest')
    expect(response.headers['Cache-Control']).to include('private', 'no-store')
  end

  it 'links changed venues, programs, participant settings, and dated exceptions to their current pages' do
    program = create_program
    membership = grant_participant_access(program, create_user)
    exception = track_record(ProgramScheduleException.create!(program: program, mode: 'closed',
                                                              date: Date.current.next_occurring(:monday),
                                                              reason: 'Studio closed.'))
    change_program_records(program, membership, exception)
    sign_in(admin)
    get admin_history_path
    expect(history_row(program.venue.history_tracks.last).at_css("a[href='#{venue_path(program.venue)}']"))
      .to be_present
    expect(history_row(program.history_tracks.last).at_css("a[href='#{program_path(program)}']")).to be_present
    expect(history_row(membership.history_tracks.last).css('a').pluck('href'))
      .to include(admin_user_path(membership.user), program_path(program),
                  edit_program_participant_path(program, membership))
    expect(history_row(exception.history_tracks.last).css('a').pluck('href'))
      .to include(program_schedule_path(program, date: exception.date.iso8601))
  end

  it 'retains a revoked membership history link without offering unavailable participant settings' do
    membership = grant_participant_access(create_program, create_user)
    membership.update!(roles: [])
    sign_in(admin)
    get admin_history_path
    row = history_row(membership.history_tracks.last)
    expect(row.css('a').pluck('href')).to include(admin_user_path(membership.user), program_path(membership.program))
    expect(row.css('a').pluck('href')).not_to include(edit_program_participant_path(membership.program, membership))
  end

  it 'retains deletion snapshots and missing actors without broken links or record lookup errors' do
    user = create_user(name: 'Retained Subject')
    actor = create_user(name: 'Former Editor')
    Current.set(user: actor) { user.destroy! }
    entry = user.history_tracks.last
    actor.destroy!
    sign_in(admin)
    get admin_history_path
    row = history_row(entry)
    expect(row.text).to include('Deleted account', actor.id.to_s, 'Retained Subject', 'Unavailable', 'Deleted')
    expect(row.css('a')).to be_empty
    expect(row.text).to include('Before:', 'After: Not set')
    expect(response.body).to include('System / Anonymous')
  end

  it 'does not resolve unknown or embedded history classes or display their raw field payloads' do
    entry = track_record(HistoryTracker.create!(association_chain: [{ name: 'Unknown', id: BSON::ObjectId.new }],
                                                action: 'update', modified: { name: 'hidden payload' }))
    chain = [{ name: 'User', id: admin.id }, { name: 'photos', id: BSON::ObjectId.new }]
    embedded = track_record(HistoryTracker.create!(association_chain: chain, action: 'update',
                                                   modified: { name: 'hidden payload' }))
    missing = track_record(HistoryTracker.create!(association_chain: [], action: 'update',
                                                  modified: { name: 'hidden payload' }))
    sign_in(admin)
    get admin_history_path
    expect(history_row(entry).text).to include('No displayable field changes.', 'Unavailable')
    expect(history_row(embedded).text).to include('No displayable field changes.', 'Unavailable')
    expect(history_row(missing).text).to include('Unknown record', 'No displayable field changes.', 'Unavailable')
    expect(history_row(entry).text).not_to include('Unknown')
    expect(response.body).not_to include('hidden payload')
  end

  it 'paginates without shifting after later changes and never writes an audit entry for viewing' do
    stub_const('CursorPage::PER_PAGE', 2)
    users = Array.new(3) { create_user }
    sign_in(admin)
    original_ids = HistoryTracker.order_by(created_at: :desc, id: :desc).pluck(:id).map(&:to_s)
    expect { get admin_history_path }.not_to change(HistoryTracker, :count)
    next_path = response.parsed_body.at_css('a[rel="next"]')['href']
    Current.set(user: admin) { users.first.update!(name: 'Changed while paging') }
    get next_path
    expect(response.parsed_body.css('tr[data-history]').pluck('data-history')).to eq(original_ids[2, 2])
    expect(response.parsed_body.at_css('a[rel="prev"]')).to be_present
    admin.update!(roles: [])
    get next_path
    expect(response).to have_http_status(:forbidden)
  end

  it 'renders an empty state without requiring or inventing an audit baseline' do
    administrator = Mongoid::History.disable { create_user(roles: ['system_admin']) }
    sign_in(administrator)
    get admin_history_path
    expect(response.body).to include('No changes in this view.')
    expect(response.parsed_body.at_css('table')).to be_nil
    expect(response.parsed_body.at_css('.participant-pagination')).to be_nil
  end

  it 'batch loads actors and subjects rather than reading each user per row' do
    users = Array.new(8) { create_user }
    Current.set(user: admin) { users.each { |user| user.update!(name: 'Changed User') } }
    sign_in(admin)
    reads = []
    monitor = double(succeeded: nil, failed: nil)
    allow(monitor).to receive(:started) do |event|
      reads << event.command_name if event.command[event.command_name] == 'users'
    end
    Mongoid.default_client.subscribe(Mongo::Monitoring::COMMAND, monitor)
    get admin_history_path
    expect(response.parsed_body.css('tr[data-history]').size).to eq(17)
    expect(reads.size).to be <= 3
  ensure
    Mongoid.default_client.unsubscribe(Mongo::Monitoring::COMMAND, monitor) if monitor
  end
end
