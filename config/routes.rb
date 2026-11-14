# frozen_string_literal: true

Rails.application.routes.draw do
  root 'pages#home'
  resource :registration, only: %i[new create]
  resource :session, only: %i[new create destroy]
  resources :password_resets, param: :token, only: %i[new create edit update]
  get 'up' => 'rails/health#show', as: :rails_health_check
end
