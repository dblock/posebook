# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Session management', :aggregate_failures, :database, type: :request do
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
    drawing_session = create_drawing_session(start_time: '19:15', time_zone: 'America/Los_Angeles',
                                             available_weekdays: %w[3 1])
    sign_in(create_user(roles: ['system_admin']))
    [drawing_sessions_path, drawing_session_path(
      drawing_session
    ), drawing_session_models_path(drawing_session), drawing_session_coordinators_path(drawing_session),
     new_drawing_session_model_invitation_path(
       drawing_session
     ), drawing_session_schedule_path(drawing_session)].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Monday and Wednesday at 7:15 PM (America/Los_Angeles)')
    end
    get edit_drawing_session_path(drawing_session)
    expect(response.parsed_body.at_css('input[name="drawing_session[start_time]"]')['value']).to eq('19:15')
  end

  it 'shows a working session URL beneath the slug only after the session is saved' do
    sign_in(create_user(roles: ['system_admin']))
    get new_venue_drawing_session_path(create_venue)
    expect(response.parsed_body.at_css('#drawing_session_custom_slug ~ small a')).to be_nil
    [create_drawing_session, create_drawing_session(custom_slug: 'weekly-drawing')].each do |drawing_session|
      get edit_drawing_session_path(drawing_session)
      link = response.parsed_body.at_css('#drawing_session_custom_slug ~ small a')
      expect(link['href']).to eq(drawing_session_path(drawing_session))
      expect(link.text).to eq("#{request.base_url}#{drawing_session_path(drawing_session)}")
      get link['href']
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(drawing_session.name)
    end
  end

  it 'requires authentication for management but allows public session shortcuts' do
    create_user
    get drawing_sessions_path
    expect(response).to redirect_to(new_session_path)
    get drawing_session_coordinators_path(create_drawing_session)
    expect(response).to redirect_to(new_session_path)
    get drawing_session_path(create_drawing_session)
    expect(response).to have_http_status(:ok)
  end

  it 'lets a system admin create and update session settings' do
    sign_in(create_user(roles: ['system_admin']))
    venue = create_venue
    get new_venue_drawing_session_path(venue)
    expect(response).to have_http_status(:ok)
    attributes = { name: "Enoch's", time_zone: 'America/New_York', model_pay: '140.00' }
    post venue_drawing_sessions_path(venue), params: { drawing_session: attributes }
    drawing_session = track_record(DrawingSession.find_by(name: "Enoch's"))
    expect(response).to redirect_to(drawing_session_path(drawing_session))
    get edit_drawing_session_path(drawing_session)
    expect(response).to have_http_status(:ok)
    patch drawing_session_path(
      drawing_session
    ), params: { drawing_session: { instructions: 'Please arrive at 6:15 PM.', booking_horizon_months: 9,
                                    available_weekdays: ['', '1', '3'] } }
    expect(drawing_session.reload.booking_horizon_months).to eq(9)
    expect(drawing_session.instructions).to eq('Please arrive at 6:15 PM.')
    expect(drawing_session.available_weekdays).to eq(%w[1 3])
  end

  it 'renders validation errors when creating or editing a drawing_session' do
    sign_in(create_user(roles: ['system_admin']))
    post venue_drawing_sessions_path(create_venue), params: { drawing_session: { name: '', time_zone: 'invalid' } }
    expect(response).to have_http_status(:unprocessable_content)
    drawing_session = create_drawing_session
    patch drawing_session_path(drawing_session), params: { drawing_session: { name: '' } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'limits organizers to managing their assigned sessions while allowing public information elsewhere' do
    drawing_session = create_drawing_session
    other = create_drawing_session
    user = create_user
    grant_coordinator_access(drawing_session, user)
    sign_in(user)
    get drawing_sessions_path
    expect(response.body).to include(drawing_session.name)
    expect(response.body).not_to include(other.name)
    get drawing_session_path(drawing_session)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Edit Session')
    expect(response.body).not_to include('Existing user', 'Session Coordinators')
    get drawing_session_coordinators_path(drawing_session)
    expect(response).to have_http_status(:forbidden)
    get drawing_session_path(other)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Instructions', 'Model Pay', 'Edit Day', 'Booking History')
  end

  it 'allows session editing but does not grant venue or coordinator administration' do
    drawing_session = create_drawing_session
    user = create_user
    grant_coordinator_access(drawing_session, user)
    sign_in(user)
    get new_venue_path
    expect(response).to have_http_status(:forbidden)
    post venue_drawing_sessions_path(drawing_session.venue), params: { drawing_session: { name: 'Forbidden' } }
    expect(response).to have_http_status(:not_found)
    patch drawing_session_path(drawing_session), params: { drawing_session: { name: 'Updated Session' } }
    expect(response).to redirect_to(drawing_session_path(drawing_session.reload))
    post drawing_session_coordinators_path(drawing_session), params: { user_id: user.id }
    expect(response).to have_http_status(:forbidden)
  end

  it 'shows an empty session list to users without assignments' do
    sign_in(create_user)
    get drawing_sessions_path
    expect(response.body).to include('No sessions assigned')
  end

  it 'lets a system admin grant and revoke schedule access without deleting membership history' do
    sign_in(create_user(roles: ['system_admin']))
    drawing_session = create_drawing_session
    user = create_user
    post drawing_session_coordinators_path(drawing_session), params: { user_id: user.id, roles: ['system_admin'] }
    membership = track_record(DrawingSessionMembership.find_by(drawing_session_id: drawing_session.id,
                                                               user_id: user.id))
    expect(response).to redirect_to(drawing_session_coordinators_path(drawing_session))
    expect(membership.roles).to eq(['session_coordinator'])
    expect(user.reload.roles).to be_empty
    delete drawing_session_coordinator_path(drawing_session, membership)
    expect(response).to redirect_to(drawing_session_coordinators_path(drawing_session))
    expect(membership.reload.roles).to be_empty
    expect(DrawingSession.visible_to(user)).to be_empty
  end

  it 'does not let organizer removal target a membership at another drawing_session' do
    sign_in(create_user(roles: ['system_admin']))
    drawing_session = create_drawing_session
    membership = grant_coordinator_access(create_drawing_session, create_user)
    delete drawing_session_coordinator_path(drawing_session, membership)
    expect(response).to have_http_status(:not_found)
    expect(membership.reload.roles).to eq(['session_coordinator'])
  end

  it 'does not assign inactive users' do
    sign_in(create_user(roles: ['system_admin']))
    drawing_session = create_drawing_session
    user = create_user(active: false)
    post drawing_session_coordinators_path(drawing_session), params: { user_id: user.id }
    expect(response).to have_http_status(:not_found)
    expect(DrawingSessionMembership.where(drawing_session_id: drawing_session.id)).to be_empty
  end

  it 'shows assignment controls only to admins and labels inactive organizers' do
    sign_in(create_user(roles: ['system_admin']))
    drawing_session = create_drawing_session
    user = create_user
    grant_coordinator_access(drawing_session, user)
    user.set(active: false)
    get drawing_session_coordinators_path(drawing_session)
    expect(response.parsed_body.text).to include('Inactive account', 'Remove Coordinator')
    expect(response.parsed_body.css('select[name="user_id"]')).to be_empty
  end

  it 'links to a separate organizer page beside session editing without exposing controls on the session' do
    sign_in(create_user(roles: ['system_admin']))
    drawing_session = create_drawing_session
    user = create_user
    get drawing_session_path(drawing_session)
    links = response.parsed_body.css('main > p').find { |paragraph| paragraph.text.include?('Edit Session') }
    expect(links.css('a').pluck('href')).to eq([edit_drawing_session_path(drawing_session)])
    expect(response.body).to include(drawing_session_coordinators_path(drawing_session))
    expect(response.body).not_to include('Grant Schedule Access', 'Remove Schedule Access', user.email)
    get drawing_session_coordinators_path(drawing_session)
    expect(response.body).to include('Add Session Coordinator')
    expect(response.body).not_to include(user.email)
    expect(response.parsed_body.css('main a').last['href']).to eq(drawing_session_path(drawing_session))
    sign_in(user)
    get drawing_session_coordinators_path(drawing_session)
    expect(response).to have_http_status(:forbidden)
  end

  it 'resolves public session slugs and legacy IDs without exposing management or root shortcuts' do
    drawing_session = create_drawing_session
    user = create_user
    grant_coordinator_access(drawing_session, user)
    sign_in(user)
    [drawing_session_path(drawing_session), drawing_session_path(drawing_session.id)].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(drawing_session.name)
    end
    other = create_drawing_session
    get drawing_session_path(other)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Edit Session', 'Manage Schedule')
    get "/#{drawing_session.slug}"
    expect(response).to have_http_status(:not_found)
  end

  it 'lets admins edit slugs while retaining old URLs and using slugs in nested management links' do
    sign_in(create_user(roles: ['system_admin']))
    drawing_session = create_drawing_session
    previous = drawing_session.slug
    patch drawing_session_path(drawing_session), params: { drawing_session: { custom_slug: 'Weekly Drawing' } }
    expect(response).to redirect_to('/sessions/weekly-drawing')
    get "/sessions/#{previous}"
    expect(response).to have_http_status(:ok)
    get "/#{previous}"
    expect(response).to have_http_status(:not_found)
    get drawing_session_coordinators_path(drawing_session.reload)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css('main form')['action']).to eq('/sessions/weekly-drawing/coordinators')
  end

  it 'keeps built-in routes reachable when a session requests a reserved slug' do
    sign_in(create_user(roles: ['system_admin']))
    drawing_session = create_drawing_session(custom_slug: 'drawing_sessions')
    get drawing_sessions_path
    expect(response.body).to include('Sessions', drawing_session.name)
    get '/up'
    expect(response).to have_http_status(:ok)
    get drawing_session_path(drawing_session)
    expect(response.body).to include(drawing_session.name)
  end

  it 'renders a friendly error if another request claims the slug before insertion' do
    sign_in(create_user(roles: ['system_admin']))
    other = create_drawing_session
    allow(DrawingSession).to receive(:new).and_wrap_original do |constructor, *arguments|
      constructor.call(*arguments).tap do |drawing_session|
        allow(drawing_session).to receive(:find_unique_slug).and_wrap_original do |generate|
          generate.call.tap { |slug| other.set(_slugs: [slug]) }
        end
      end
    end
    post venue_drawing_sessions_path(create_venue), params: { drawing_session: { name: 'Racing Session' } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('has already been taken')
    expect(DrawingSession.where(name: 'Racing Session')).to be_empty
  end
end
