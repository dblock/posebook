# frozen_string_literal: true

Rails.application.routes.draw do
  root 'pages#home'
  resource :registration, only: %i[new create]
  resource :session, only: %i[new create destroy]
  resource :profile, only: %i[edit update]
  resource :password, only: :update
  resource :account_deactivation, only: :create
  resource :email_change, only: %i[show update]
  namespace :admin do
    resources :users, only: %i[index update]
  end
  resources :password_resets, param: :token, only: %i[new create edit update]
  get 'up' => 'rails/health#show', as: :rails_health_check
end
