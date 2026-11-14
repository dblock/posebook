# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Session management', :aggregate_failures, :database, type: :request do
  context 'with configurable terminology' do
    let(:program) { create_program(program_label: 'Workshop', participant_label: 'Instructor') }
    let(:organizer) { create_user }
    let(:participant) { create_user }

    before do
      grant_coordinator_access(program, organizer)
      grant_participant_access(program, participant)
      sign_in(organizer)
    end

    it 'lets assigned coordinators edit labels and uses them in settings and calendars' do
      patch program_path(program), params: { program: { program_label: 'Lecture', participant_label: 'Speaker' } }
      expect(response).to redirect_to(program_path(program))
      follow_redirect!
      expect(response.body).to include('Lecture settings saved.', 'Lecture Calendar', 'Schedule a Speaker')
      expect(response.parsed_body.css('dt').map(&:text)).to include('Pay')
      get edit_program_path(program)
      expect(response.parsed_body.at_css('input[name="program[participant_label]"]')['value']).to eq('Speaker')
      expect(response.body).to include('Save Lecture', 'Prevent Consecutive Speakers by Gender')
    end

    it 'uses configured roster and booking labels without changing membership roles' do
      get program_participants_path(program)
      expect(response.body).to include('Instructors at', 'total instructors', 'Pause Instructor')
      get new_program_organizer_booking_path(program)
      expect(response.parsed_body.at_css('label[for="booking_user_id"]').text).to eq('Instructor')
      expect(response.body).to include('Choose an instructor')
      expect(program.memberships.find_by(user_id: participant.id).roles).to eq(['participant'])
    end

    it 'uses configured labels in invitation emails and acceptance pages' do
      invitation = create_participant_invitation(program, organizer, email: 'invited@example.test')
      message = ParticipantInvitationMailer.invite(invitation, invitation.token)
      expect(message.subject).to include('as an instructor')
      expect(message.body.encoded).to include(program.name)
      delete session_path
      get invitation_path(token: invitation.token)
      expect(response.body).to include('join the workshop as an instructor')
    end
  end

  it 'rejects invalid labels and prevents unrelated users from changing terminology' do
    program = create_program
    sign_in(create_user(roles: ['system_admin']))
    patch program_path(program), params: { program: { program_label: '', participant_label: '<script>' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(program.reload).to have_attributes(program_label: 'Session', participant_label: 'Model')
    delete session_path
    sign_in(create_user)
    patch program_path(program), params: { program: { participant_label: 'Speaker' } }
    expect(response).to have_http_status(:not_found)
    expect(program.reload.participant_label).to eq('Model')
  end

  it 'normalizes session Instagram handles and URLs and publishes safe external links without account preferences' do
    venue = create_venue
    sign_in(create_user(roles: ['system_admin']))
    [' @ENOCHS.NYC ', 'https://www.instagram.com/Enochs.NYC/?source=profile'].each do |value|
      patch venue_path(venue), params: { venue: { instagram_handle: value } }
      expect(venue.reload.instagram_handle).to eq('enochs.nyc')
    end
    delete session_path
    get venue_path(venue)
    link = response.parsed_body.at_css('a[href="https://www.instagram.com/enochs.nyc/"]')
    expect(link.text).to eq('@enochs.nyc')
    expect(link['target']).to eq('_blank')
    expect(link['rel'].split).to include('noopener', 'noreferrer')
  end

  it 'rejects invalid session Instagram accounts and removes the public link when cleared' do
    venue = create_venue(instagram_handle: '@enochs.nyc')
    sign_in(create_user(roles: ['system_admin']))
    %w[https://example.test/account https://instagram.com/p/post/].each do |value|
      patch venue_path(venue), params: { venue: { instagram_handle: value } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(venue.reload.instagram_handle).to eq('enochs.nyc')
    end
    patch venue_path(venue), params: { venue: { instagram_handle: '' } }
    delete session_path
    get venue_path(venue)
    expect(response.body).not_to include('instagram.com/enochs.nyc')
  end

  it 'shows the configured usual weekdays, event time, and time zone across session pages' do
    program = create_program(start_time: '19:15', time_zone: 'America/Los_Angeles',
                             available_weekdays: %w[3 1])
    sign_in(create_user(roles: ['system_admin']))
    [programs_path, program_path(
      program
    ), program_participants_path(program), program_coordinators_path(program),
     new_program_participant_invitation_path(
       program
     ), program_schedule_path(program)].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Monday and Wednesday at 7:15 PM (America/Los_Angeles)')
    end
    get edit_program_path(program)
    expect(response.parsed_body.at_css('input[name="program[start_time]"]')['value']).to eq('19:15')
  end

  it 'shows a working session URL beneath the slug only after the session is saved' do
    sign_in(create_user(roles: ['system_admin']))
    get new_venue_program_path(create_venue)
    expect(response.parsed_body.at_css('#program_custom_slug ~ small a')).to be_nil
    [create_program, create_program(custom_slug: 'weekly-drawing')].each do |program|
      get edit_program_path(program)
      link = response.parsed_body.at_css('#program_custom_slug ~ small a')
      expect(link['href']).to eq(program_path(program))
      expect(link.text).to eq("#{request.base_url}#{program_path(program)}")
      get link['href']
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(program.name)
    end
  end

  it 'requires authentication for management but allows public session shortcuts' do
    create_user
    get programs_path
    expect(response).to redirect_to(new_session_path)
    get program_coordinators_path(create_program)
    expect(response).to redirect_to(new_session_path)
    get program_path(create_program)
    expect(response).to have_http_status(:ok)
  end

  it 'lets a system admin create and update session settings' do
    sign_in(create_user(roles: ['system_admin']))
    venue = create_venue
    get new_venue_program_path(venue)
    expect(response).to have_http_status(:ok)
    attributes = { name: "Enoch's", time_zone: 'America/New_York', pay: '140.00' }
    post venue_programs_path(venue), params: { program: attributes }
    program = track_record(Program.find_by(name: "Enoch's"))
    expect(response).to redirect_to(program_path(program))
    get edit_program_path(program)
    expect(response).to have_http_status(:ok)
    patch program_path(
      program
    ), params: { program: { instructions: 'Please arrive at 6:15 PM.', booking_horizon_months: 9,
                            available_weekdays: ['', '1', '3'] } }
    expect(program.reload.booking_horizon_months).to eq(9)
    expect(program.instructions).to eq('Please arrive at 6:15 PM.')
    expect(program.available_weekdays).to eq(%w[1 3])
  end

  it 'renders validation errors when creating or editing a program' do
    sign_in(create_user(roles: ['system_admin']))
    post venue_programs_path(create_venue), params: { program: { name: '', time_zone: 'invalid' } }
    expect(response).to have_http_status(:unprocessable_content)
    program = create_program
    patch program_path(program), params: { program: { name: '' } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'limits organizers to managing their assigned sessions while allowing public information elsewhere' do
    program = create_program
    other = create_program
    user = create_user
    grant_coordinator_access(program, user)
    sign_in(user)
    get programs_path
    expect(response.body).to include(program.name)
    expect(response.body).not_to include(other.name)
    get program_path(program)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Edit Session')
    expect(response.body).not_to include('Existing user', 'Session Coordinators')
    get program_coordinators_path(program)
    expect(response).to have_http_status(:forbidden)
    get program_path(other)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Instructions', 'Pay', 'Edit Day', 'Booking History')
  end

  it 'allows session editing but does not grant venue or coordinator administration' do
    program = create_program
    user = create_user
    grant_coordinator_access(program, user)
    sign_in(user)
    get new_venue_path
    expect(response).to have_http_status(:forbidden)
    post venue_programs_path(program.venue), params: { program: { name: 'Forbidden' } }
    expect(response).to have_http_status(:not_found)
    patch program_path(program), params: { program: { name: 'Updated Session' } }
    expect(response).to redirect_to(program_path(program.reload))
    post program_coordinators_path(program), params: { user_id: user.id }
    expect(response).to have_http_status(:forbidden)
  end

  it 'shows an empty session list to users without assignments' do
    sign_in(create_user)
    get programs_path
    expect(response.body).to include('No sessions assigned')
  end

  it 'lets a system admin grant and revoke schedule access without deleting membership history' do
    sign_in(create_user(roles: ['system_admin']))
    program = create_program
    user = create_user
    post program_coordinators_path(program), params: { user_id: user.id, roles: ['system_admin'] }
    membership = track_record(ProgramMembership.find_by(program_id: program.id,
                                                        user_id: user.id))
    expect(response).to redirect_to(program_coordinators_path(program))
    expect(membership.roles).to eq(['program_coordinator'])
    expect(user.reload.roles).to be_empty
    delete program_coordinator_path(program, membership)
    expect(response).to redirect_to(program_coordinators_path(program))
    expect(membership.reload.roles).to be_empty
    expect(Program.visible_to(user)).to be_empty
  end

  it 'does not let organizer removal target a membership at another program' do
    sign_in(create_user(roles: ['system_admin']))
    program = create_program
    membership = grant_coordinator_access(create_program, create_user)
    delete program_coordinator_path(program, membership)
    expect(response).to have_http_status(:not_found)
    expect(membership.reload.roles).to eq(['program_coordinator'])
  end

  it 'does not assign inactive users' do
    sign_in(create_user(roles: ['system_admin']))
    program = create_program
    user = create_user(active: false)
    post program_coordinators_path(program), params: { user_id: user.id }
    expect(response).to have_http_status(:not_found)
    expect(ProgramMembership.where(program_id: program.id)).to be_empty
  end

  it 'shows assignment controls only to admins and labels inactive organizers' do
    sign_in(create_user(roles: ['system_admin']))
    program = create_program
    user = create_user
    grant_coordinator_access(program, user)
    user.set(active: false)
    get program_coordinators_path(program)
    expect(response.parsed_body.text).to include('Inactive account', 'Remove Coordinator')
    expect(response.parsed_body.css('select[name="user_id"]')).to be_empty
  end

  it 'links to a separate organizer page beside session editing without exposing controls on the session' do
    sign_in(create_user(roles: ['system_admin']))
    program = create_program
    user = create_user
    get program_path(program)
    links = response.parsed_body.css('main > p').find { |paragraph| paragraph.text.include?('Edit Session') }
    expect(links.css('a').pluck('href')).to eq([edit_program_path(program)])
    expect(response.body).to include(program_coordinators_path(program))
    expect(response.body).not_to include('Grant Schedule Access', 'Remove Schedule Access', user.email)
    get program_coordinators_path(program)
    expect(response.body).to include('Invite or Promote a Coordinator', 'Continue')
    expect(response.body).not_to include(user.email)
    expect(response.parsed_body.css('main a').last['href']).to eq(program_path(program))
    sign_in(user)
    get program_coordinators_path(program)
    expect(response).to have_http_status(:forbidden)
  end

  it 'resolves public session slugs and legacy IDs without exposing management or root shortcuts' do
    program = create_program
    user = create_user
    grant_coordinator_access(program, user)
    sign_in(user)
    [program_path(program), program_path(program.id)].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(program.name)
    end
    other = create_program
    get program_path(other)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Edit Session', 'Manage Schedule')
    get "/#{program.slug}"
    expect(response).to have_http_status(:not_found)
  end

  it 'lets admins edit slugs while retaining old URLs and using slugs in nested management links' do
    sign_in(create_user(roles: ['system_admin']))
    program = create_program
    previous = program.slug
    patch program_path(program), params: { program: { custom_slug: 'Weekly Drawing' } }
    expect(response).to redirect_to('/sessions/weekly-drawing')
    get "/sessions/#{previous}"
    expect(response).to have_http_status(:ok)
    get "/#{previous}"
    expect(response).to have_http_status(:not_found)
    get program_coordinators_path(program.reload)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css('main form')['action']).to eq('/sessions/weekly-drawing/coordinators')
  end

  it 'keeps built-in routes reachable when a session requests a reserved slug' do
    sign_in(create_user(roles: ['system_admin']))
    program = create_program(custom_slug: 'programs')
    get programs_path
    expect(response.body).to include('Sessions', program.name)
    get '/up'
    expect(response).to have_http_status(:ok)
    get program_path(program)
    expect(response.body).to include(program.name)
  end

  it 'renders a friendly error if another request claims the slug before insertion' do
    sign_in(create_user(roles: ['system_admin']))
    other = create_program
    allow(Program).to receive(:new).and_wrap_original do |constructor, *arguments|
      constructor.call(*arguments).tap do |program|
        allow(program).to receive(:find_unique_slug).and_wrap_original do |generate|
          generate.call.tap { |slug| other.set(_slugs: [slug]) }
        end
      end
    end
    post venue_programs_path(create_venue), params: { program: { name: 'Racing Session' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('has already been taken')
    expect(Program.where(name: 'Racing Session')).to be_empty
  end
end
