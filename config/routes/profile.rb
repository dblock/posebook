# frozen_string_literal: true

resource(:profile, only: %i[show edit update]) do
  get :security
  get :bookings
  get :history
  get :details
  get :programs
end
resource :password, only: %i[edit update]
resource :account_deactivation, only: %i[new create]
get 'profile/photos', to: 'participant_profiles#photos', as: :photos_profile
