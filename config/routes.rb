# frozen_string_literal: true

Rails.application.routes.draw do
  root 'pages#home'
  %i[invitations google_calendar].each { |routes| draw routes }
  resource :session, only: %i[new create destroy]
  resource :profile, only: %i[show edit update]
  resources :participants, only: :show, controller: 'participant_profiles' do
    resources :photos, only: %i[show create update destroy], controller: 'profile_photos'
  end
  resource :password, only: %i[edit update]
  resource :account_deactivation, only: %i[new create]
  resource :email_change, only: %i[show update]
  namespace(:admin) { resources :users, only: %i[index edit update] }
  resources :venues, except: :destroy do
    resources :photos, only: %i[show create destroy], controller: 'venue_photos'
    resources :coordinators, only: %i[index create destroy], controller: 'venue_coordinators'
    resources :coordinator_invitations, only: %i[show destroy]
    resources :programs, path: 'sessions', only: %i[new create]
  end
  resources :programs, path: 'sessions', only: %i[index show edit update] do
    resource :schedule, controller: 'program_schedules', only: %i[show update]
    resources(:organizer_bookings, only: %i[new create edit update]) { post :cancel, on: :member }
    resources :participants, controller: 'program_participants', only: :index do
      post :invite_all, on: :collection
      %i[invite pause resume].each { |action| post action, on: :member }
    end
    resources :participant_invitations, controller: 'program_invitations', only: %i[new create show destroy]
    resources :bookings, only: %i[create edit update] do
      get :cancellation, on: :member
      %i[cancel confirm].each { |action| post action, on: :member }
    end
    resources :coordinators, controller: 'program_coordinators', only: %i[index create destroy]
    resources :coordinator_invitations, only: %i[show destroy]
  end
  resources :password_resets, param: :token, only: %i[new create edit update]
  get 'up' => 'rails/health#show', as: :rails_health_check
end
