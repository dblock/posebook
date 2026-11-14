# frozen_string_literal: true

resource :registration, only: %i[new create]
resource :invitation, only: %i[show create], controller: 'invitation_acceptances'
post 'invitation/register', to: 'invitation_acceptances#register', as: :invited_registration
resource :coordinator_invitation, only: %i[show create], controller: 'coordinator_invitation_acceptances'
post 'coordinator_invitation/register', to: 'coordinator_invitation_acceptances#register',
                                        as: :coordinator_invited_registration
