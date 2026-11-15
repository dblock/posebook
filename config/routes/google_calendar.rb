# frozen_string_literal: true

get 'google_calendar/callback', to: 'google_calendar_callbacks#show', as: :google_calendar_callback
resources :programs, only: [] do
  resource :google_calendar, controller: 'google_calendars', only: %i[show create destroy]
end
