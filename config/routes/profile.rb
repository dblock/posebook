# frozen_string_literal: true

resource(:profile, only: %i[show edit update]) do
  get :security
  get :history
end
resource :password, only: %i[edit update]
resource :account_deactivation, only: %i[new create]
