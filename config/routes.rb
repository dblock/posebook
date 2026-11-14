# frozen_string_literal: true

Rails.application.routes.draw do
  root 'pages#home'
  resource :registration, only: %i[new create]
  resource :session, only: %i[new create destroy]
  resource :profile, only: %i[show edit update]
  resource :password, only: %i[edit update]
  resource :account_deactivation, only: %i[new create]
  resource :email_change, only: %i[show update]
  resource :invitation, only: %i[show create], controller: 'invitation_acceptances'
  post 'invitation/register', to: 'invitation_acceptances#register', as: :invited_registration
  namespace :admin do
    resources :users, only: %i[index edit update]
  end
  resources :venues, except: :destroy do
    resources :model_invitations, controller: 'venue_invitations', only: %i[new create show destroy]
    resources :organizers, controller: 'venue_organizers', only: %i[create destroy]
  end
  resources :password_resets, param: :token, only: %i[new create edit update]
  get 'up' => 'rails/health#show', as: :rails_health_check
end
