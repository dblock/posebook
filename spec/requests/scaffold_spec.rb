# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Application scaffold', :aggregate_failures, type: :request do
  it 'sends a blank installation to first-user registration' do
    get '/'

    expect(response).to redirect_to(new_registration_path)
  end

  it 'exposes the Rails liveness endpoint' do
    get '/up'

    expect(response).to have_http_status(:ok)
  end

  it 'serves the local theme with an accessible account form and navigation' do
    get new_session_path

    html = response.parsed_body
    stylesheets = html.css('link[rel="stylesheet"]').pluck('href')
    expect(html.root['data-theme']).to eq('caramellatte')
    expect(html.at_css('header nav[aria-label="Account"] a.brand').text.strip).to eq('Posebook')
    expect(html.at_css('.page-shell main form input[type="password"]')).to be_present
    expect(stylesheets).to all(start_with('/assets/'))

    theme = stylesheets.find { |path| path.include?('/caramellatte-') }
    expect(theme).to be_present
    get theme
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('--color-base-100')
  end
end
