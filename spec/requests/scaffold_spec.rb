# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Application scaffold', :aggregate_failures, type: :request do
  it 'renders an honest placeholder without offering registration' do
    get '/'

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<h1>Posebook</h1>', 'Registration and booking are not available yet.')
  end

  it 'exposes the Rails liveness endpoint' do
    get '/up'

    expect(response).to have_http_status(:ok)
  end
end
