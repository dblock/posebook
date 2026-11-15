# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Homepage programs', :aggregate_failures, :database, type: :request do
  let(:user) { create_user }

  def program_names(section)
    response.parsed_body.css(".#{section}-programs .program-card h2 a").map(&:text)
  end

  it 'lists direct and inherited coordinator programs once without exposing unassigned siblings' do
    venue = create_venue
    inherited = %w[Alpha Beta].map { |name| create_program(venue: venue, name: name) }
    direct = create_program(name: 'Gamma')
    foreign = create_program(venue: direct.venue, name: 'Unassigned Sibling', instructions: 'Private sibling note')
    grant_venue_access(venue, user)
    grant_coordinator_access(inherited.first, user)
    grant_coordinator_access(direct, user)
    sign_in(user)
    get root_path(program_id: foreign.id)
    expect(program_names('managed')).to eq(%w[Alpha Beta Gamma])
    expect(response.parsed_body.css('.managed-programs .button-link').pluck('href'))
      .to eq([*inherited, direct].map { |program| program_path(program, section: 'calendar') })
    expect(response.body).not_to include(foreign.name, 'Private sibling note')
  end

  it 'removes management cards on the next request when coordinator access is revoked' do
    program = create_program
    membership = grant_coordinator_access(program, user)
    sign_in(user)
    get root_path
    expect(program_names('managed')).to eq([program.name])
    membership.update!(roles: [])
    get root_path
    expect(response.parsed_body.at_css('.managed-programs')).to be_nil
  end

  it 'retains management access to inactive programs and programs at inactive venues' do
    programs = [create_program(name: 'Alpha', active: false),
                create_program(name: 'Beta', venue: create_venue(active: false))]
    programs.each { |program| grant_coordinator_access(program, user) }
    sign_in(user)
    get root_path
    expect(program_names('managed')).to eq(%w[Alpha Beta])
    expect(response.parsed_body.css('.managed-programs .status-label').map(&:text)).to eq(%w[Inactive Inactive])
    expect(response.parsed_body.at_css('.bookable-programs')).to be_nil
  end

  it 'shows separate booking and management actions for an account with both roles' do
    program = create_program
    grant_coordinator_access(program, user)
    grant_participant_access(program, user)
    sign_in(user)
    get root_path
    expect(program_names('bookable')).to eq([program.name])
    expect(program_names('managed')).to eq([program.name])
    expect(response.parsed_body.at_css('.bookable-programs .button-link').text).to eq('Choose a Date')
    expect(response.parsed_body.at_css('.managed-programs .button-link').text).to eq('Manage Calendar')
  end

  it 'does not grant a regular account management cards through another user ID or supplied roles' do
    program = create_program
    coordinator = create_user
    grant_coordinator_access(program, coordinator)
    sign_in(user)
    get root_path, params: { user_id: coordinator.id, roles: ['system_admin'], program_id: program.id }
    expect(response.parsed_body.css('.managed-programs, .bookable-programs')).to be_empty
    expect(response.body).not_to include(program.name, coordinator.email)
  end

  it 'lists every program for a system administrator without granting participant booking access' do
    programs = [create_program(name: 'Alpha'), create_program(name: 'Beta', active: false)]
    sign_in(create_user(roles: ['system_admin']))
    get root_path
    expect(program_names('managed')).to include(*programs.map(&:name))
    expect(program_names('managed').size).to eq(Program.count)
    expect(response.parsed_body.at_css('.bookable-programs')).to be_nil
  end

  it 'lists future-opening bookable programs but excludes inactive programs and venues' do
    programs = [create_program(first_bookable_date: Date.current.next_year), create_program(active: false),
                create_program(venue: create_venue(active: false))]
    programs.each { |program| grant_participant_access(program, user) }
    sign_in(user)
    get root_path
    expect(program_names('bookable')).to eq([programs.first.name])
    card = response.parsed_body.at_css('.bookable-programs .program-card')
    expect(card.at_css('img')['src']).to include('program-placeholder')
    expect(card.at_css('.button-link')['href']).to eq(program_path(programs.first, section: 'calendar'))
    expect(response.parsed_body.at_css('.managed-programs')).to be_nil
  end
end
