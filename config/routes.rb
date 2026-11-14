# frozen_string_literal: true

Rails.application.routes.draw do
  root 'pages#home'
  resource :registration, only: %i[new create]
  resource :session, only: %i[new create destroy]
  resource :profile, only: %i[show edit update]
  resource :password, only: %i[edit update]
  resource :account_deactivation, only: %i[new create]
  resource :email_change, only: %i[show update]
  namespace :admin do
    resources :users, only: %i[index update]
  end
  resources :venues, except: :destroy do
    resources :organizers, controller: 'venue_organizers', only: %i[create destroy]
  end
  resources :password_resets, param: :token, only: %i[new create edit update]
  get 'up' => 'rails/health#show', as: :rails_health_check
end
