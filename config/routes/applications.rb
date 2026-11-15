# frozen_string_literal: true

resource :application_verification, only: %i[show create]
post 'application_verification/register', to: 'application_verifications#register',
                                          as: :application_registration_account
resources :programs, only: [] do
  resource :application_registration, only: %i[new create]
  resource :participation_application, controller: 'participant_applications', only: %i[new create show destroy]
  resources :applications, controller: 'program_applications', only: %i[index show update] do
    get :history, on: :collection
  end
end
get 'profile/applications', to: 'participant_applications#index', as: :applications_profile
