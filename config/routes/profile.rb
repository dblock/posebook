# frozen_string_literal: true

resource(:profile, only: %i[show edit update]) { get :security }
resource :password, only: %i[edit update]
resource :account_deactivation, only: %i[new create]
