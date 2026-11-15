# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public information pages', :aggregate_failures, :database, type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2027, 1, 1, 12)) { example.run } }

  it 'provides About, privacy, and terms without an account and links them in the footer' do
    { about_path => 'About Posebook', privacy_path => 'Privacy Policy',
      terms_path => 'Terms of Service' }.each do |path, title|
      get path
      expect(response).to have_http_status(:ok)
      page = response.parsed_body
      expect(page.at_css('main h1').text).to eq(title)
      expect(page.at_css('main').text).to include('Vestris LLC.')
      expect(page.at_css('footer nav span').text).to eq("Copyright \u00a9 2027 Vestris LLC.")
      expect(page.at_css('main a[href="mailto:drawing@dblock.org"]')).to be_present
      expect(page.css('footer a').pluck('href')).to contain_exactly(about_path, privacy_path, terms_path)
    end
  end

  it 'provides project and policy links on About without exposing private support requests' do
    get about_path
    page = response.parsed_body
    expect(page.at_css('main a[href="https://github.com/dblock/posebook"]')).to be_present
    expect(page.at_css('main a[href="https://github.com/dblock/posebook/issues"]')).to be_present
    expect(page.at_css('main a[href="https://www.vestris.com/"]')).to be_present
    expect(page.at_css("main a[href='#{privacy_path}']")).to be_present
    expect(page.at_css("main a[href='#{terms_path}']")).to be_present
    expect(response.body).to include('GitHub issues are public.')
  end

  it 'keeps the home page protected and provides the same information links for signed-in users' do
    user = create_user
    get root_path
    expect(response).to redirect_to(new_session_path)
    sign_in(user)
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.at_css('footer nav span').text).to eq("Copyright \u00a9 2027 Vestris LLC.")
    expect(response.parsed_body.css('footer a').pluck('href')).to contain_exactly(about_path, privacy_path, terms_path)
    get privacy_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(user.name)
  end
end
