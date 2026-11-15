# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Stored audit history', :aggregate_failures, :database, type: :request do
  it 'attributes self-service profile changes to the signed-in user and rejects supplied actor fields' do
    user = create_user
    other = create_user
    sign_in(user)
    patch profile_path, params: { user: { name: 'Updated Profile', email: user.email,
                                          modifier_id: other.id, version: 999 } }
    expect(response).to redirect_to(details_profile_path)
    change = user.history_tracks.last
    expect(change.modified).to eq('name' => 'Updated Profile')
    expect(change).to have_attributes(modifier_id: user.id, version: 2)
    expect(change.created_at).to be_present
  end

  it 'attributes admin changes to the admin without leaking that actor to another session' do
    admin = create_user(roles: ['system_admin'])
    user = create_user
    program = create_program
    sign_in(admin)
    patch admin_user_path(user), params: { user: { name: 'Admin Edit', email: user.email } }
    expect(user.history_tracks.last.modifier_id).to eq(admin.id)
    patch program_path(program),
          params: { program: { instructions: 'Updated session instructions.' } }
    expect(program.history_tracks.last.modifier_id).to eq(admin.id)
    other_client = ActionDispatch::Integration::Session.new(Rails.application)
    sign_in(user, client: other_client)
    other_client.patch(profile_path, params: { user: { name: 'Self Edit', email: user.email } })
    expect(user.history_tracks.last.modifier_id).to eq(user.id)
    expect(Current.user).to be_nil
  end
end
