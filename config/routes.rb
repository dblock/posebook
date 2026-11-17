# frozen_string_literal: true

Rails.application.routes.draw do
  root 'pages#home'
  %i[invitations applications google_calendar profile information].each { |routes| draw routes }
  resource :session, only: %i[new create destroy]
  resources :participants, only: :show, controller: 'participant_profiles' do
    resources :photos, only: %i[show create update destroy], controller: 'profile_photos'
  end
  resource :email_change, only: %i[show update]
  namespace :admin do
    get 'history', to: 'history#index', as: :history
    resources :users, only: %i[index show edit update] do
      member do
        %i[bookings programs applications history photos security].each { |page| get page }
        post :password_reset
      end
    end
  end
  resources :venues, except: :destroy do
    %i[photos programs security].each { |page| get page, on: :member }
    resources :photos, only: %i[show create update destroy], controller: 'venue_photos'
    resources :coordinators, only: %i[index new create destroy], controller: 'venue_coordinators'
    resources :coordinator_invitations, only: %i[show destroy]
    resources :programs, only: %i[new create]
  end
  resources :programs, only: %i[index show edit update] do
    get :calendar, on: :member, action: :show, defaults: { section: 'calendar' }
    get :history, on: :member, action: :show, defaults: { section: 'history' }
    get :photos, on: :member
    get :security, on: :member
    resources :photos, only: %i[show create update destroy], controller: 'program_photos'
    resource(:schedule, controller: 'program_schedules', only: %i[show update]) { get :exceptions }
    resources(:organizer_bookings, only: %i[new create edit update]) { post :cancel, on: :member }
    resources :participants, controller: 'program_participants', only: %i[index edit update] do
      post :invite_all, on: :collection
      %i[invite pause resume].each { |action| post action, on: :member }
    end
    resources :participant_invitations, controller: 'program_invitations', only: %i[index new create show destroy]
    resources :bookings, only: %i[create edit update] do
      get :cancellation, on: :member
      %i[cancel confirm].each { |action| post action, on: :member }
    end
    resources :coordinators, controller: 'program_coordinators', only: %i[index new create destroy]
    resources :coordinator_invitations, only: %i[show destroy]
  end
  resources :password_resets, param: :token, only: %i[new create edit update]
  get 'up' => 'rails/health#show', as: :rails_health_check
end
