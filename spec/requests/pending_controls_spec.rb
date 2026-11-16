# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Pending action feedback', :aggregate_failures, :database, type: :request do
  it 'loads deferred submission feedback on anonymous forms without disabling their native controls' do
    get new_session_path
    script = response.parsed_body.at_css('script[src*="/pending-controls-"]')
    expect(script['defer']).to be_present
    expect(response.parsed_body.at_css('input[type="submit"]')['disabled']).to be_nil
    get script['src']
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to include('javascript')
  end

  it 'enables shared feedback on uploads and small action forms while retaining no-script submission' do
    user = create_user
    sign_in(user)
    get photos_profile_path
    expect(response.parsed_body.at_css('script[src*="/pending-controls-"][defer]')).to be_present
    upload = response.parsed_body.at_css('input[type="file"]').ancestors('form').first
    expect(upload.at_css('input[type="file"]')).to be_present
    expect(upload.at_css('input[type="submit"]')['disabled']).to be_nil
    expect(response.parsed_body.at_css('.site-nav form button')['disabled']).to be_nil
  end
end
