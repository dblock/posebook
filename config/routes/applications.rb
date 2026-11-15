# frozen_string_literal: true

resource :application_verification, only: %i[show create]
post 'application_verification/register', to: 'application_verifications#register',
                                          as: :application_registration_account
resources :programs, only: [] do
  resource :application_registration, only: %i[new create]
end
