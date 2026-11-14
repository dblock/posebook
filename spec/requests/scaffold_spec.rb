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
end
